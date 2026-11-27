//! Snapshot adapter for Mortal libriichi's PlayerState decision logic.
//! Based on state/update.rs (tsumo, dahai, chi, pon, kakan and set_can_chi_from_tile).
//! History-dependent flags are inputs because the wire format is a snapshot.

use crate::algo::agari::forms;
use crate::model::{
    Counts, Meld, Request, Result, counts, kind, notation, one, player_shanten, tile,
    validate_tiles,
};
use crate::tile::Tile;
use std::collections::BTreeSet;

#[derive(Default)]
struct ChiCandidates {
    can_chi_low: bool,
    can_chi_mid: bool,
    can_chi_high: bool,
}

include!("chi_candidates.rs");

pub fn legal(req: &Request<'_>) -> Result<String> {
    let mut state = PlayerState {
        req,
        actions: BTreeSet::new(),
        wall: req.number("wall", 70)?,
        kans: req.number("kans", 0)?,
        riichi: req.boolean("riichi")?,
        concealed: counts(req.hand.iter().copied()),
        chi: ChiCandidates::default(),
    };
    match (
        req.fields.get("draw"),
        req.fields.get("discard"),
        req.fields.get("called"),
    ) {
        (Some(draw), None, None) => state.tsumo(one(draw)?)?,
        (None, Some(discard), None) => state.dahai(one(discard)?)?,
        (None, None, Some(called)) => {
            state.called(&Meld::parse(called)?, one(req.get("took", ""))?)?
        }
        _ => return Err("bad_decision"),
    }
    if state.actions.is_empty() {
        return Err("no_legal_action");
    }
    Ok(format!(
        "actions={}",
        state.actions.into_iter().collect::<Vec<_>>().join(",")
    ))
}

struct PlayerState<'a, 'b> {
    req: &'a Request<'b>,
    actions: BTreeSet<String>,
    wall: u32,
    kans: u32,
    riichi: bool,
    concealed: Counts,
    chi: ChiCandidates,
}

impl PlayerState<'_, '_> {
    fn can_kan(&self) -> bool {
        self.wall >= 1 && self.kans < 4
    }

    fn can_win(&self, concealed: &Counts, win: Tile, ron: bool, situational: bool) -> bool {
        if player_shanten(concealed, self.req.groups()) != -1 {
            return false;
        }
        self.riichi
            || situational
            || !ron && self.req.closed()
            || self
                .req
                .evaluate(concealed, win, ron)
                .iter()
                .any(|e| !e.yaku.is_empty() || !e.yakuman.is_empty())
    }

    fn tsumo(&mut self, draw: Tile) -> Result<()> {
        self.req.check_size(0)?;
        validate_tiles(self.req.owned(Some(draw)))?;
        let mut hand = self.req.hand.clone();
        hand.push(draw);
        let mut after = self.concealed;
        after[kind(draw)] += 1;
        let first = self.req.boolean("first")?;
        if self.can_win(
            &after,
            draw,
            false,
            self.req.flag("haitei") || self.req.flag("rinshan") || self.wall == 0,
        ) {
            self.actions.insert("tsumo".into());
        }
        if first
            && after
                .iter()
                .enumerate()
                .filter(|&(i, &n)| n > 0 && tile(i as u8).is_yaokyuu())
                .count()
                >= 9
        {
            self.actions.insert("kyuushu".into());
        }

        let groups = self.req.groups();
        for &t in &hand {
            if !self.riichi || t == draw {
                self.actions.insert(format!("discard:{}", notation(&[t])));
            }
            if !self.riichi && self.req.closed() && self.wall >= 4 {
                let mut remaining = after;
                remaining[kind(t)] -= 1;
                if player_shanten(&remaining, groups) == 0 {
                    self.actions.insert(format!("riichi:{}", notation(&[t])));
                }
            }
            if self.can_kan()
                && !self.riichi
                && self
                    .req
                    .melds
                    .iter()
                    .any(|m| m.form == b'p' && kind(m.tiles[0]) == kind(t))
            {
                self.actions.insert(format!("kakan:{}", notation(&[t])));
            }
        }
        if self.can_kan() {
            let owned = counts(self.req.owned(None));
            for (i, &n) in after.iter().enumerate() {
                if n == 4
                    && (!self.riichi || i == kind(draw) && strict_ankan(&self.concealed, &owned, i))
                {
                    self.actions
                        .insert(format!("ankan:{}", notation(&[tile(i as u8)])));
                }
            }
        }
        Ok(())
    }

    fn dahai(&mut self, discard: Tile) -> Result<()> {
        self.req.check_size(0)?;
        let from = self.req.get("from", "");
        if !matches!(from, "kamicha" | "toimen" | "shimocha") {
            return Err("bad_from");
        }
        validate_tiles(self.req.owned(Some(discard)))?;
        let mut with_win = self.concealed;
        let i = kind(discard);
        with_win[i] += 1;
        let chankan = self.req.flag("chankan");
        self.actions.insert("pass".into());
        if !self.req.boolean("furiten")?
            && self.can_win(
                &with_win,
                discard,
                true,
                chankan || self.req.flag("houtei") || self.wall == 0,
            )
        {
            self.actions.insert("ron".into());
        }
        if chankan || self.riichi || self.wall == 0 || self.req.groups() == 0 {
            return Ok(());
        }

        if self.can_kan() && self.concealed[i] == 3 {
            self.actions
                .insert(format!("kan:{}", notation(&[discard.deaka()])));
        }
        if from == "kamicha" && !discard.is_jihai() {
            self.set_can_chi_from_tile(discard);
        }
        let hand = &self.req.hand;
        for (a, &left) in hand.iter().enumerate() {
            for &right in &hand[a + 1..] {
                let mut kinds = [i, kind(left), kind(right)];
                kinds.sort_unstable();
                let [low, mid, high] = kinds;
                if low == high {
                    self.actions
                        .insert(format!("pon:{}", notation(&[left, right])));
                } else if from == "kamicha"
                    && high < 27
                    && low / 9 == high / 9
                    && low + 1 == mid
                    && mid + 1 == high
                {
                    let can_chi = if i == low {
                        self.chi.can_chi_low
                    } else if i == mid {
                        self.chi.can_chi_mid
                    } else {
                        self.chi.can_chi_high
                    };
                    if can_chi {
                        self.actions
                            .insert(format!("chi:{}", notation(&[left, right])));
                    }
                }
            }
        }
        Ok(())
    }

    fn called(&mut self, meld: &Meld, took: Tile) -> Result<()> {
        self.req.check_size(1)?;
        if !matches!(meld.form, b'c' | b'p')
            || !self.req.melds.contains(meld)
            || !meld.tiles.contains(&took)
        {
            return Err("bad_call");
        }
        let sequence = (meld.form == b'c').then(|| kind(meld.tiles[0]));
        let forbidden = kuikae(kind(took), sequence);
        for &t in &self.req.hand {
            if !forbidden.contains(&kind(t)) {
                self.actions.insert(format!("discard:{}", notation(&[t])));
            }
        }
        Ok(())
    }
}

fn kuikae(took: usize, sequence: Option<usize>) -> Vec<usize> {
    let mut forbidden = vec![took];
    if let Some(low) = sequence {
        if took == low && low % 9 < 6 {
            forbidden.push(low + 3);
        } else if took == low + 2 && low % 9 > 0 {
            forbidden.push(low - 1);
        }
    }
    forbidden
}

// Compare the actual divisions, with the original fixed triplet removed.
// A viable wait must remain viable, and no original alternative may disappear.
fn strict_ankan(before: &Counts, owned: &Counts, kan: usize) -> bool {
    let mut found = false;
    for (wait, &n) in owned.iter().enumerate() {
        if n == 4 {
            continue;
        }
        let mut original = *before;
        original[wait] += 1;
        let (kokushi, chiitoi, original_forms) = forms(&original);
        if kokushi || chiitoi || wait == kan && !original_forms.is_empty() {
            return false;
        }
        if wait == kan {
            continue;
        }
        let mut remaining = original;
        remaining[kan] = 0;
        let (_, _, new_forms) = forms(&remaining);
        let mut projected = BTreeSet::new();
        for mut form in original_forms {
            let Some(pos) = form
                .iter()
                .position(|&(id, class)| id as usize == kan && class == 2)
            else {
                return false;
            };
            form.remove(pos);
            projected.insert(form);
        }
        if !projected.is_empty() {
            found = true;
        }
        if projected != new_forms.into_iter().collect() {
            return false;
        }
    }
    found
}
