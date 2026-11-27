#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Placement {
    Pair,
    Triplet,
    GoodSequence,
    BadSequence,
}

pub struct Evaluation {
    pub yaku: Vec<(&'static str, u8)>,
    pub yakuman: Vec<(&'static str, u8)>,
    pub fu: u8,
}

// (Tile, group class), in the contract's pair/sequence/triplet order.
pub type Form = Vec<(u8, u8)>;

fn form_for_div(ordered: &[u8; 14], div: &Div) -> Form {
    let mut form = vec![(ordered[div.pair_idx as usize], 0)];
    form.extend(div.shuntsu_idxs.iter().map(|&i| (ordered[i as usize], 1)));
    form.extend(div.kotsu_idxs.iter().map(|&i| (ordered[i as usize], 2)));
    form.sort_unstable();
    form
}

fn enumerate_groups(tiles: [u8; 34], form: &mut Form, forms: &mut Vec<Form>) {
    let Some(first) = tiles.iter().position(|&n| n > 0) else {
        let mut completed = form.clone();
        completed.sort_unstable();
        forms.push(completed);
        return;
    };
    if tiles[first] >= 3 {
        let mut remaining = tiles;
        remaining[first] -= 3;
        form.push((first as u8, 2));
        enumerate_groups(remaining, form, forms);
        form.pop();
    }
    if first < 27 && first % 9 < 7 && tiles[first + 1] > 0 && tiles[first + 2] > 0 {
        let mut remaining = tiles;
        for n in &mut remaining[first..first + 3] {
            *n -= 1;
        }
        form.push((first as u8, 1));
        enumerate_groups(remaining, form, forms);
        form.pop();
    }
}

fn normal_divisions(tiles: &[u8; 34], ordered: &[u8; 14], key: u32) -> Vec<Div> {
    let mut divisions: Vec<_> = AGARI_TABLE.get(&key).into_iter().flatten()
        .filter(|d| !d.has_chitoi).cloned().collect();
    if divisions.is_empty() {
        return divisions;
    }

    // The lookup table is designed for scoring, so it omits some equivalent
    // divisions. The protocol and the strict ankan rule need all divisions.
    let mut forms = Vec::new();
    for (pair, &n) in tiles.iter().enumerate().filter(|&(_, &n)| n >= 2) {
        let mut remaining = *tiles;
        remaining[pair] = n - 2;
        enumerate_groups(remaining, &mut vec![(pair as u8, 0)], &mut forms);
    }

    let mut known: std::collections::BTreeSet<_> = divisions.iter()
        .map(|div| form_for_div(ordered, div)).collect();
    let has_chuuren = divisions.iter().any(|div| div.has_chuuren);
    let index = |id| ordered.iter().position(|&t| t == id).unwrap() as u8;
    for form in forms {
        if !known.insert(form.clone()) {
            continue;
        }
        let pair = form.iter().find(|&&(_, class)| class == 0).unwrap().0;
        let sequences: Vec<_> = form.iter().filter_map(|&(t, class)| (class == 1).then_some(t)).collect();
        let triplets = form.iter().filter_map(|&(t, class)| (class == 2).then_some(index(t))).collect();
        divisions.push(Div {
            pair_idx: index(pair),
            kotsu_idxs: triplets,
            shuntsu_idxs: sequences.iter().copied().map(index).collect(),
            has_chitoi: false,
            has_chuuren,
            has_ittsuu: [0, 9, 18].into_iter().any(|start| {
                [start, start + 3, start + 6].iter().all(|t| sequences.contains(t))
            }),
            has_ipeikou: sequences.windows(2).any(|w| w[0] == w[1]),
            has_ryanpeikou: sequences.len() == 4 && sequences[0] == sequences[1]
                && sequences[2] == sequences[3],
        });
    }
    divisions
}

pub fn forms(tiles: &[u8; 34]) -> (bool, bool, Vec<Form>) {
    let (ordered, key) = get_tile14_and_key(tiles);
    let forms = normal_divisions(tiles, &ordered, key)
        .iter().map(|div| form_for_div(&ordered, div)).collect();
    (shanten::calc_kokushi(tiles) == -1, shanten::calc_chitoi(tiles) == -1, forms)
}

impl AgariCalculator<'_> {
    pub fn evaluations(&self) -> Vec<Evaluation> {
        let win = self.winning_tile;
        if shanten::calc_kokushi(self.tehai) == -1 {
            let thirteen = self.tehai[win as usize] == 2;
            return vec![Evaluation {
                yaku: Vec::new(),
                yakuman: vec![(if thirteen { "kokushi_13" } else { "kokushi" }, if thirteen { 2 } else { 1 })],
                fu: 0,
            }];
        }
        let (ordered, key) = get_tile14_and_key(self.tehai);
        let mut results = Vec::new();
        let synthetic_chiitoi = Div { has_chitoi: true, ..Div::default() };
        let normal = normal_divisions(self.tehai, &ordered, key);
        let divisions = normal.iter().chain(
            (shanten::calc_chitoi(self.tehai) == -1).then_some(&synthetic_chiitoi),
        );
        for div in divisions {
            let mut worker = DivWorker::new(self, &ordered, div, Placement::Pair);
            let mut placements = Vec::new();
            if div.has_chitoi || worker.pair_tile == win {
                placements.push(Placement::Pair);
            }
            if worker.menzen_kotsu.contains(&win) {
                placements.push(Placement::Triplet);
            }
            for &start in &worker.menzen_shuntsu {
                if (start..=start + 2).contains(&win) {
                    let bad = win == start + 1 || start % 9 == 0 && win == start + 2
                        || start % 9 == 6 && win == start;
                    placements.push(if bad { Placement::BadSequence } else { Placement::GoodSequence });
                }
            }
            placements.sort_unstable();
            placements.dedup();
            for placement in placements {
                worker.placement = placement;
                let mut evaluation = worker.evaluate();
                for (name, multiple) in &mut evaluation.yakuman {
                    match *name {
                        "suuankou" if placement == Placement::Pair => {
                            *name = "suuankou_tanki";
                            *multiple = 2;
                        }
                        "daisuushii" => *multiple = 2,
                        "chuuren" => {
                            let start = (win / 9 * 9) as usize;
                            if [3, 1, 1, 1, 1, 1, 1, 1, 3].iter().enumerate().all(
                                |(i, &count)| self.tehai[start + i] == count + u8::from(start + i == win as usize)
                            ) {
                                *name = "junsei_chuuren";
                                *multiple = 2;
                            }
                        }
                        _ => {}
                    }
                }
                results.push(evaluation);
            }
        }
        results
    }
}
