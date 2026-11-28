//! Rust port of EndlessCheng's Go port of 山岡忠夫's Java implementation of his
//! agari algorithm.
//!
//! Source:
//! * Go: <https://github.com/EndlessCheng/mahjong-helper/blob/master/util/agari.go>
//! * Java: <http://hp.vector.co.jp/authors/VA046927/mjscore/AgariIndex.java>
//! * Algorithm: <http://hp.vector.co.jp/authors/VA046927/mjscore/mjalgorism.html>

use super::shanten;
use crate::{matches_tu8, must_tile, tu8};
use std::iter;
use std::sync::LazyLock;

use std::collections::HashMap;
use std::io::{Cursor, Read};

static AGARI_TABLE: LazyLock<HashMap<u32, Vec<Div>>> = LazyLock::new(|| {
    let mut raw = Cursor::new(include_bytes!(concat!(env!("OUT_DIR"), "/agari.bin")));
    fn read_u32(raw: &mut impl Read) -> u32 {
        let mut buf = [0; 4];
        raw.read_exact(&mut buf).unwrap();
        u32::from_le_bytes(buf)
    }
    (0..9362)
        .map(|_| {
            let key = read_u32(&mut raw);
            let mut size = [0];
            raw.read_exact(&mut size).unwrap();
            let values = (0..size[0])
                .map(|_| Div::from(read_u32(&mut raw)))
                .collect();
            (key, values)
        })
        .collect()
});

#[derive(Clone, Debug, Default)]
struct Div {
    pair_idx: u8,
    kotsu_idxs: Vec<u8>,
    shuntsu_idxs: Vec<u8>,
    has_chitoi: bool,
    has_chuuren: bool,
    has_ittsuu: bool,
    has_ryanpeikou: bool,
    // CAUTION: it is sound but not complete, broken if there is any ankan
    has_ipeikou: bool,
}

pub struct AgariCalculator<'a> {
    /// Must include the winning tile (i.e. must be 3n+2)
    pub tehai: &'a [u8; 34],
    /// `self.chis.is_empty() && self.pons.is_empty() && self.minkans.is_empty()`
    pub is_menzen: bool,
    pub chis: &'a [u8],
    pub pons: &'a [u8],
    pub minkans: &'a [u8],
    pub ankans: &'a [u8],

    pub bakaze: u8,
    pub jikaze: u8,

    /// Must be deakaized
    pub winning_tile: u8,
    /// For consistency reasons, `is_ron` is only used to calculate fu and check
    /// ankou/ankan-related yakus like 三/四暗刻. It will not be used to
    /// determine 門前清自摸和.
    pub is_ron: bool,
}

struct DivWorker<'a> {
    sup: &'a AgariCalculator<'a>,
    tile14: &'a [u8; 14],
    div: &'a Div,
    pair_tile: u8,
    menzen_kotsu: Vec<u8>,
    menzen_shuntsu: Vec<u8>,

    placement: Placement,
}

impl From<u32> for Div {
    fn from(v: u32) -> Self {
        let pair_idx = ((v >> 6) & 0b1111) as u8;

        let kotsu_count = v & 0b111;
        let kotsu_idxs = (0..kotsu_count)
            .map(|i| ((v >> (10 + i * 4)) & 0b1111) as u8)
            .collect();

        let shuntsu_count = (v >> 3) & 0b111;
        let shuntsu_idxs = (kotsu_count..kotsu_count + shuntsu_count)
            .map(|i| ((v >> (10 + i * 4)) & 0b1111) as u8)
            .collect();

        let has_chitoi = (v >> 26) & 0b1 == 0b1;
        let has_chuuren = (v >> 27) & 0b1 == 0b1;
        let has_ittsuu = (v >> 28) & 0b1 == 0b1;
        let has_ryanpeikou = (v >> 29) & 0b1 == 0b1;
        let has_ipeikou = (v >> 30) & 0b1 == 0b1;

        Self {
            pair_idx,
            kotsu_idxs,
            shuntsu_idxs,
            has_chitoi,
            has_chuuren,
            has_ittsuu,
            has_ryanpeikou,
            has_ipeikou,
        }
    }
}

impl<'a> DivWorker<'a> {
    fn new(
        calc: &'a AgariCalculator<'a>,
        tile14: &'a [u8; 14],
        div: &'a Div,
        placement: Placement,
    ) -> Self {
        let pair_tile = tile14[div.pair_idx as usize];
        let menzen_kotsu = div
            .kotsu_idxs
            .iter()
            .map(|&idx| tile14[idx as usize])
            .collect();
        let menzen_shuntsu = div
            .shuntsu_idxs
            .iter()
            .map(|&idx| tile14[idx as usize])
            .collect();

        Self {
            sup: calc,
            tile14,
            div,
            pair_tile,
            menzen_kotsu,
            menzen_shuntsu,
            placement,
        }
    }

    fn winning_tile_makes_minkou(&self) -> bool {
        self.sup.is_ron && self.placement == Placement::Triplet
    }

    /// The caller must assure `self.div.has_chitoi` holds.
    fn chitoi_pairs(&self) -> impl Iterator<Item = u8> + '_ {
        self.tile14.iter().take(7).copied()
    }

    fn all_kotsu_and_kantsu(&self) -> impl Iterator<Item = u8> + '_ {
        self.menzen_kotsu
            .iter()
            .chain(self.sup.pons)
            .chain(self.sup.minkans)
            .chain(self.sup.ankans)
            .copied()
    }

    fn all_shuntsu(&self) -> impl Iterator<Item = u8> + '_ {
        self.menzen_shuntsu.iter().chain(self.sup.chis).copied()
    }

    fn all_mentsu(&self) -> impl Iterator<Item = u8> + '_ {
        self.all_kotsu_and_kantsu().chain(self.all_shuntsu())
    }

    fn calc_fu(&self, has_pinfu: bool) -> u8 {
        if self.div.has_chitoi {
            return 25;
        }
        let mut fu = 20;

        fu += self
            .menzen_kotsu
            .iter()
            .map(|&t| {
                // `menzen_kotsu` are usually ankou, except when the winning
                // tile makes a minkou and the tile is the winning tile.
                let is_minkou = self.winning_tile_makes_minkou() && t == self.sup.winning_tile;
                match (is_minkou, must_tile!(t).is_yaokyuu()) {
                    (false, true) => 8,
                    (false, false) | (true, true) => 4,
                    (true, false) => 2,
                }
            })
            .sum::<u8>();
        fu += self
            .sup
            .pons
            .iter()
            .map(|&t| if must_tile!(t).is_yaokyuu() { 4 } else { 2 })
            .sum::<u8>();
        fu += self
            .sup
            .ankans
            .iter()
            .map(|&t| if must_tile!(t).is_yaokyuu() { 32 } else { 16 })
            .sum::<u8>();
        fu += self
            .sup
            .minkans
            .iter()
            .map(|&t| if must_tile!(t).is_yaokyuu() { 16 } else { 8 })
            .sum::<u8>();

        if matches_tu8!(self.pair_tile, P | F | C) {
            fu += 2;
        } else {
            // As per [Tenhou's rule](https://tenhou.net/man/#RULE):
            //
            // > 連風牌は4符
            if self.pair_tile == self.sup.bakaze {
                fu += 2;
            }
            if self.pair_tile == self.sup.jikaze {
                fu += 2;
            }
        }

        if fu == 20 {
            return if !self.sup.is_menzen {
                30
            } else if has_pinfu {
                if self.sup.is_ron { 30 } else { 20 }
            } else if self.sup.is_ron {
                40
            } else {
                30
            };
        }

        if !self.sup.is_ron {
            fu += 2;
        } else if self.sup.is_menzen {
            fu += 10;
        }

        if matches!(self.placement, Placement::Pair | Placement::BadSequence) {
            fu += 2;
        }

        ((fu - 1) / 10 + 1) * 10
    }

    fn evaluate(&self) -> Evaluation {
        let mut yaku = vec![];
        let mut yakuman = vec![];
        let has_pinfu = self.menzen_shuntsu.len() == 4
            && !matches_tu8!(self.pair_tile, P | F | C)
            && self.pair_tile != self.sup.bakaze
            && self.pair_tile != self.sup.jikaze
            && self.placement == Placement::GoodSequence;

        if has_pinfu {
            // 平和
            yaku.push(("pinfu", 1));
        }
        if self.div.has_chitoi {
            // 七対子
            yaku.push(("chiitoi", 2));
        }
        if self.div.has_ryanpeikou {
            // 二盃口
            yaku.push(("ryanpeikou", 3));
        }
        if self.div.has_chuuren {
            // 九蓮宝燈
            yakuman.push(("chuuren", 1));
        }

        let has_tanyao = if self.div.has_chitoi {
            self.chitoi_pairs().all(|t| {
                let kind = t / 9;
                let num = t % 9;
                kind < 3 && num > 0 && num < 8
            })
        } else {
            self.all_shuntsu().all(|s| {
                let num = s % 9;
                num > 0 && num < 6
            }) && self
                .all_kotsu_and_kantsu()
                .chain(iter::once(self.pair_tile))
                .all(|k| {
                    let kind = k / 9;
                    let num = k % 9;
                    kind < 3 && num > 0 && num < 8
                })
        };
        if has_tanyao {
            // 断幺九
            yaku.push(("tanyao", 1));
        }

        let has_toitoi =
            !self.div.has_chitoi && self.menzen_shuntsu.is_empty() && self.sup.chis.is_empty();
        if has_toitoi {
            // 対々和
            yaku.push(("toitoi", 2));
        }

        let mut isou_kind = None;
        let mut has_jihai = false;
        let mut is_chinitsu_or_honitsu = true;
        let iter_fn = |&m: &u8| {
            let kind = m / 9;
            if kind >= 3 {
                has_jihai = true;
                return true;
            }
            if let Some(prev_kind) = isou_kind {
                if prev_kind != kind {
                    is_chinitsu_or_honitsu = false;
                    return false;
                }
            } else {
                isou_kind = Some(kind);
            }
            true
        };
        if self.div.has_chitoi {
            self.chitoi_pairs().take_while(iter_fn).for_each(drop);
        } else {
            self.all_mentsu()
                .chain(iter::once(self.pair_tile))
                .take_while(iter_fn)
                .for_each(drop);
        }
        if isou_kind.is_none() {
            // 字一色
            yakuman.push(("tsuuiisou", 1));
        } else if is_chinitsu_or_honitsu {
            // 混一色, 清一色
            let n = if has_jihai { 2 } else { 5 } + self.sup.is_menzen as u8;
            yaku.push((if has_jihai { "honitsu" } else { "chinitsu" }, n));
        }

        if !self.div.has_chitoi {
            // 一盃口
            if self.sup.is_menzen && !self.div.has_ryanpeikou && self.div.has_ipeikou {
                yaku.push(("iipeikou", 1));
            } else if !self.div.has_ryanpeikou
                && !self.sup.ankans.is_empty()
                && self.sup.is_menzen
                && self.menzen_shuntsu.len() >= 2
            {
                let mut shuntsu_marks = [0_u8; 3];
                let has_ipeikou = self.menzen_shuntsu.iter().any(|&t| {
                    let kind = t as usize / 9;
                    let num = t % 9;
                    let mark = &mut shuntsu_marks[kind];
                    if (*mark >> num) & 0b1 == 0b1 {
                        true
                    } else {
                        *mark |= 0b1 << num;
                        false
                    }
                });
                if has_ipeikou {
                    yaku.push(("iipeikou", 1));
                }
            }

            // 一気通貫
            if self.sup.is_menzen && self.div.has_ittsuu {
                yaku.push(("ittsu", 2));
            } else if self.sup.chis.is_empty() && self.div.has_ittsuu {
                yaku.push(("ittsu", 1));
            } else if self.menzen_shuntsu.len() + self.sup.chis.len() >= 3 {
                let mut kinds = [0; 3];
                for s in self.all_shuntsu() {
                    let kind = s as usize / 9;
                    let num = s % 9;
                    match num {
                        0 => kinds[kind] |= 0b001,
                        3 => kinds[kind] |= 0b010,
                        6 => kinds[kind] |= 0b100,
                        _ => (),
                    };
                }
                if kinds.contains(&0b111) {
                    yaku.push(("ittsu", 1));
                }
            }

            let mut s_counter = [0; 9];
            for s in self.all_shuntsu() {
                let kind = s / 9;
                let num = s % 9;
                s_counter[num as usize] |= 0b1 << kind;
            }
            if s_counter.contains(&0b111) {
                // 三色同順
                let n = if self.sup.is_menzen { 2 } else { 1 };
                yaku.push(("sanshoku", n));
            } else {
                let mut k_counter = [0; 9];
                for k in self.all_kotsu_and_kantsu() {
                    let kind = k / 9;
                    if kind < 3 {
                        let num = k % 9;
                        k_counter[num as usize] |= 1 << kind;
                    }
                }
                if k_counter.contains(&0b111) {
                    // 三色同刻
                    yaku.push(("sanshoku_doukou", 2));
                }
            }

            let ankous_count = self.sup.ankans.len() + self.menzen_kotsu.len()
                - self.winning_tile_makes_minkou() as usize;
            match ankous_count {
                // 四暗刻
                4 => yakuman.push(("suuankou", 1)),
                // 三暗刻
                3 => yaku.push(("sanankou", 2)),
                _ => (),
            };

            let kans_count = self.sup.ankans.len() + self.sup.minkans.len();
            match kans_count {
                // 四槓子
                4 => yakuman.push(("suukantsu", 1)),
                // 三槓子
                3 => yaku.push(("sankantsu", 2)),
                _ => (),
            };

            let has_ryuisou = self
                .all_kotsu_and_kantsu()
                .chain(iter::once(self.pair_tile))
                .all(|k| matches_tu8!(k, 2s | 3s | 4s | 6s | 8s | F))
                && self.all_shuntsu().all(|s| s == tu8!(2s)); // only 234s is possible for shuntsu in ryuisou
            if has_ryuisou {
                // 緑一色
                yakuman.push(("ryuuiisou", 1));
            }

            if !has_tanyao {
                // 役牌 + 大小三元四喜
                let mut has_jihai = [false; 7];
                for k in self.all_kotsu_and_kantsu() {
                    if k >= 3 * 9 {
                        has_jihai[k as usize - 3 * 9] = true;
                    }
                }
                if has_jihai[self.sup.bakaze as usize - 3 * 9] {
                    // 役牌:門風牌
                    yaku.push(("yakuhai_round", 1));
                }
                if has_jihai[self.sup.jikaze as usize - 3 * 9] {
                    // 役牌:場風牌
                    yaku.push(("yakuhai_seat", 1));
                }

                let saneins = (4..7).filter(|&i| has_jihai[i]).count() as u8;
                if saneins > 0 {
                    // 役牌:三元牌
                    for (i, name) in ["yakuhai_haku", "yakuhai_hatsu", "yakuhai_chun"]
                        .into_iter()
                        .enumerate()
                    {
                        if has_jihai[i + 4] {
                            yaku.push((name, 1));
                        }
                    }
                    if saneins == 3 {
                        // 大三元
                        yakuman.push(("daisangen", 1));
                    } else if saneins == 2 && matches_tu8!(self.pair_tile, P | F | C) {
                        // 小三元
                        yaku.push(("shousangen", 2));
                    }
                }

                let winds = (0..4).filter(|&i| has_jihai[i]).count();
                #[allow(clippy::if_same_then_else)]
                if winds == 4 {
                    // 大四喜
                    yakuman.push(("daisuushii", 1));
                } else if winds == 3 && matches_tu8!(self.pair_tile, E | S | W | N) {
                    // 小四喜
                    yakuman.push(("shousuushii", 1));
                }
            }
        }

        if !has_tanyao {
            let mut has_jihai = false;
            let is_yaokyuu = |k| {
                let kind = k / 9;
                if kind >= 3 {
                    has_jihai = true;
                    true
                } else {
                    let num = k % 9;
                    num == 0 || num == 8
                }
            };
            let is_junchan_or_chanta_or_chinroutou_or_honroutou = if self.div.has_chitoi {
                self.chitoi_pairs().all(is_yaokyuu)
            } else {
                self.all_kotsu_and_kantsu()
                    .chain(iter::once(self.pair_tile))
                    .all(is_yaokyuu)
            };
            if is_junchan_or_chanta_or_chinroutou_or_honroutou {
                if self.div.has_chitoi || has_toitoi {
                    if has_jihai {
                        // 混老頭
                        yaku.push(("honroutou", 2));
                    } else {
                        // 清老頭
                        yakuman.push(("chinroutou", 1));
                    }
                } else {
                    let is_junchan_or_chanta = self.all_shuntsu().all(|s| {
                        let num = s % 9;
                        num == 0 || num == 6
                    });
                    if is_junchan_or_chanta {
                        // 混全帯幺九, 純全帯幺九
                        let n = if has_jihai { 1 } else { 2 } + self.sup.is_menzen as u8;
                        yaku.push((if has_jihai { "chanta" } else { "junchan" }, n));
                    }
                }
            }
        }

        Evaluation {
            yaku,
            yakuman,
            fu: self.calc_fu(has_pinfu),
        }
    }
}

fn get_tile14_and_key(tiles: &[u8; 34]) -> ([u8; 14], u32) {
    let mut tile14 = [0; 14];
    let mut tile14_iter = tile14.iter_mut();
    let mut key = 0;

    let mut bit_idx = -1;
    let mut prev_in_hand = None;
    for (kind, chunk) in tiles.as_chunks::<9>().0.iter().enumerate() {
        for (num, c) in chunk.iter().copied().enumerate() {
            if c > 0 {
                prev_in_hand = Some(());
                *tile14_iter.next().unwrap() = (kind * 9 + num) as u8;
                bit_idx += 1;

                match c {
                    2 => {
                        key |= 0b11 << bit_idx;
                        bit_idx += 2;
                    }
                    3 => {
                        key |= 0b1111 << bit_idx;
                        bit_idx += 4;
                    }
                    4 => {
                        key |= 0b11_1111 << bit_idx;
                        bit_idx += 6;
                    }
                    // 1
                    _ => (),
                }
            } else if prev_in_hand.take().is_some() {
                key |= 0b1 << bit_idx;
                bit_idx += 1;
            }
        }
        if prev_in_hand.take().is_some() {
            key |= 0b1 << bit_idx;
            bit_idx += 1;
        }
    }

    tiles
        .iter()
        .enumerate()
        .skip(3 * 9)
        .filter(|&(_, &c)| c > 0)
        .for_each(|(tile_id, &c)| {
            *tile14_iter.next().unwrap() = tile_id as u8;
            bit_idx += 1;

            match c {
                2 => {
                    key |= 0b11 << bit_idx;
                    bit_idx += 2;
                }
                3 => {
                    key |= 0b1111 << bit_idx;
                    bit_idx += 4;
                }
                4 => {
                    key |= 0b11_1111 << bit_idx;
                    bit_idx += 6;
                }
                // 1
                _ => (),
            }
            key |= 0b1 << bit_idx;
            bit_idx += 1;
        });

    (tile14, key)
}

include!("evaluation.rs");
