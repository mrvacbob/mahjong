use crate::algo::{agari::AgariCalculator, shanten};
use crate::tile::Tile;
use std::collections::BTreeMap;

pub type Result<T> = std::result::Result<T, &'static str>;
pub type Counts = [u8; 34];

pub fn tile(id: u8) -> Tile {
    Tile::try_from(id).expect("valid tile index")
}

pub fn kind(t: Tile) -> usize {
    t.deaka().as_usize()
}

fn from_digit(digit: u8, suit: usize) -> Result<Tile> {
    match digit {
        b'0' if suit < 3 => Ok(tile(34 + suit as u8)),
        b'1'..=b'9' if suit < 3 || digit <= b'7' => Ok(tile((9 * suit) as u8 + digit - b'1')),
        _ => Err("bad_tile"),
    }
}

pub fn tiles(input: &str) -> Result<Vec<Tile>> {
    if input == "-" {
        return Ok(Vec::new());
    }
    let mut result = Vec::new();
    let mut digits = Vec::new();
    for byte in input.bytes() {
        if byte.is_ascii_digit() {
            digits.push(byte);
        } else {
            let suit = b"mpsz".iter().position(|&b| b == byte).ok_or("bad_tile")?;
            if digits.is_empty() {
                return Err("bad_tile");
            }
            for digit in digits.drain(..) {
                result.push(from_digit(digit, suit)?);
            }
        }
    }
    if !digits.is_empty() || result.is_empty() {
        return Err("bad_tile");
    }
    Ok(result)
}

pub fn one(input: &str) -> Result<Tile> {
    if input.len() != 2 {
        return Err("bad_tile");
    }
    tiles(input)?.into_iter().next().ok_or("bad_tile")
}

pub fn notation(tiles: &[Tile]) -> String {
    let mut result = String::new();
    for (suit, letter) in "mpsz".chars().enumerate() {
        let mut group: Vec<_> = tiles
            .iter()
            .copied()
            .filter(|&t| kind(t) / 9 == suit)
            .collect();
        group.sort_unstable_by_key(|t| (kind(*t), !t.is_aka()));
        if !group.is_empty() {
            for t in group {
                result.push(if t.is_aka() {
                    '0'
                } else {
                    (b'1' + (kind(t) % 9) as u8) as char
                });
            }
            result.push(letter);
        }
    }
    if result.is_empty() {
        "-".into()
    } else {
        result
    }
}

pub fn counts(tiles: impl IntoIterator<Item = Tile>) -> Counts {
    let mut counts = [0; 34];
    for t in tiles {
        counts[kind(t)] += 1;
    }
    counts
}

pub fn validate_tiles(tiles: impl IntoIterator<Item = Tile>) -> Result<()> {
    let mut counts = [0; 34];
    let mut reds = [false; 3];
    for t in tiles {
        counts[kind(t)] += 1;
        if counts[kind(t)] > 4 {
            return Err("too_many_copies");
        }
        if t.is_aka() && std::mem::replace(&mut reds[t.as_usize() - 34], true) {
            return Err("too_many_reds");
        }
    }
    if reds
        .iter()
        .enumerate()
        .any(|(suit, &red)| !red && counts[4 + suit * 9] == 4)
    {
        return Err("too_many_plain_fives");
    }
    Ok(())
}

#[derive(PartialEq, Eq)]
pub struct Meld {
    pub form: u8,
    pub tiles: Vec<Tile>,
}

impl Meld {
    pub fn parse(input: &str) -> Result<Self> {
        let form = *input.as_bytes().first().ok_or("bad_meld")?;
        if !matches!(form, b'c' | b'p' | b'k' | b's' | b'a') {
            return Err("bad_meld");
        }
        let mut tiles = tiles(&input[1..])?;
        tiles.sort_unstable_by_key(|&t| (kind(t), !t.is_aka()));
        let index = kind(*tiles.first().ok_or("bad_meld")?);
        let valid = match form {
            b'c' => {
                tiles.len() == 3
                    && index < 27
                    && index % 9 <= 6
                    && kind(tiles[1]) == index + 1
                    && kind(tiles[2]) == index + 2
            }
            _ => {
                let len = if form == b'p' { 3 } else { 4 };
                tiles.len() == len && tiles.iter().all(|&t| kind(t) == index)
            }
        };
        if !valid {
            return Err("bad_meld");
        }
        Ok(Self { form, tiles })
    }
}

pub struct Request<'a> {
    pub hand: Vec<Tile>,
    pub melds: Vec<Meld>,
    pub fields: BTreeMap<&'a str, &'a str>,
    pub seat: u8,
    pub round: u8,
}

impl<'a> Request<'a> {
    pub fn parse(args: impl Iterator<Item = &'a str>) -> Result<Self> {
        let mut fields = BTreeMap::new();
        for arg in args {
            let (key, value) = arg.split_once('=').ok_or("bad_field")?;
            if key.is_empty() || value.is_empty() || fields.insert(key, value).is_some() {
                return Err("bad_field");
            }
        }
        let hand = tiles(fields.get("hand").ok_or("missing_hand")?)?;
        let melds = match fields.get("melds").copied().unwrap_or("-") {
            "-" => Vec::new(),
            s => s.split(',').map(Meld::parse).collect::<Result<Vec<_>>>()?,
        };
        if melds.len() > 4 || hand.len() > 14 {
            return Err("bad_hand_size");
        }
        validate_tiles(
            hand.iter()
                .copied()
                .chain(melds.iter().flat_map(|m| m.tiles.iter().copied())),
        )?;
        let wind = |key| match fields.get(key).copied().unwrap_or("E") {
            "E" => Ok(27),
            "S" => Ok(28),
            "W" => Ok(29),
            "N" => Ok(30),
            _ => Err("bad_wind"),
        };
        let seat = wind("seat")?;
        let round = wind("round")?;
        Ok(Self {
            hand,
            melds,
            fields,
            seat,
            round,
        })
    }

    pub fn get(&self, key: &str, default: &'a str) -> &'a str {
        self.fields.get(key).copied().unwrap_or(default)
    }

    pub fn number(&self, key: &str, default: u32) -> Result<u32> {
        self.fields
            .get(key)
            .map_or(Ok(default), |s| s.parse().map_err(|_| "bad_number"))
    }

    pub fn boolean(&self, key: &str) -> Result<bool> {
        match self.get(key, "0") {
            "0" => Ok(false),
            "1" => Ok(true),
            _ => Err("bad_boolean"),
        }
    }

    pub fn flag(&self, name: &str) -> bool {
        self.get("flags", "-").split(',').any(|flag| flag == name)
    }

    pub fn owned(&self, extra: Option<Tile>) -> impl Iterator<Item = Tile> + '_ {
        self.hand
            .iter()
            .copied()
            .chain(self.melds.iter().flat_map(|m| m.tiles.iter().copied()))
            .chain(extra)
    }

    pub fn groups(&self) -> u8 {
        4 - self.melds.len() as u8
    }

    pub fn check_size(&self, extra: usize) -> Result<()> {
        if self.hand.len() == 1 + 3 * self.groups() as usize + extra {
            Ok(())
        } else {
            Err("bad_hand_size")
        }
    }

    pub fn closed(&self) -> bool {
        self.melds.iter().all(|m| m.form == b'a')
    }

    pub fn evaluate(
        &self,
        counts: &Counts,
        win: Tile,
        ron: bool,
    ) -> Vec<crate::algo::agari::Evaluation> {
        let meld_ids = |forms: &[u8]| {
            self.melds
                .iter()
                .filter(|m| forms.contains(&m.form))
                .map(|m| kind(m.tiles[0]) as u8)
                .collect::<Vec<_>>()
        };
        AgariCalculator {
            tehai: counts,
            is_menzen: self.closed(),
            chis: &meld_ids(b"c"),
            pons: &meld_ids(b"p"),
            minkans: &meld_ids(b"ks"),
            ankans: &meld_ids(b"a"),
            bakaze: self.round,
            jikaze: self.seat,
            winning_tile: kind(win) as u8,
            is_ron: ron,
        }
        .evaluations()
    }
}

pub fn shantens(counts: &Counts, groups: u8) -> (i8, Option<i8>, Option<i8>, i8) {
    shanten_breakdown(counts, groups, crate::shape::standard(counts, groups))
}

pub fn wait_copies<'a>(
    hand: &'a Counts,
    groups: u8,
    owned: &'a Counts,
    shanten: i8,
) -> impl Iterator<Item = (usize, u8)> + 'a {
    owned.iter().enumerate().filter_map(move |(i, &n)| {
        if n == 4 {
            return None;
        }
        let mut after = *hand;
        after[i] += 1;
        (shantens(&after, groups).3 < shanten).then_some((i, 4 - n))
    })
}

fn shanten_breakdown(
    counts: &Counts,
    groups: u8,
    standard: i8,
) -> (i8, Option<i8>, Option<i8>, i8) {
    if groups < 4 {
        return (standard, None, None, standard);
    }
    let chiitoi = shanten::calc_chitoi(counts);
    let kokushi = shanten::calc_kokushi(counts);
    (
        standard,
        Some(chiitoi),
        Some(kokushi),
        standard.min(chiitoi).min(kokushi),
    )
}
