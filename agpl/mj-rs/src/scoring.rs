use std::cmp::Reverse;

use crate::model::{Request, Result, counts, kind, one, tile, tiles, validate_tiles};

pub fn score(req: &Request<'_>) -> Result<String> {
    req.check_size(0)?;
    let win = one(req.get("win", ""))?;
    let ron = match req.get("by", "") {
        "ron" => true,
        "tsumo" => false,
        _ => return Err("bad_by"),
    };
    validate_tiles(req.owned(Some(win)))?;
    let concealed = counts(req.hand.iter().copied().chain([win]));
    let dealer = req.seat == 27;
    let outcomes = if !ron && dealer && req.closed() && req.flag("tenhou") {
        concealed
            .iter()
            .enumerate()
            .filter(|&(_, &n)| n > 0)
            .flat_map(|(i, _)| req.evaluate(&concealed, tile(i as u8), ron))
            .collect()
    } else {
        req.evaluate(&concealed, win, ron)
    };
    if outcomes.is_empty() {
        return Err("not_agari");
    }
    let honba = i64::from(req.number("honba", 0)?);
    let mut situational = Vec::new();
    let riichi = req.flag("riichi") || req.flag("double_riichi");
    if req.closed() {
        if req.flag("double_riichi") {
            situational.push(("double_riichi", 2));
        } else if riichi {
            situational.push(("riichi", 1));
        }
        if riichi && req.flag("ippatsu") {
            situational.push(("ippatsu", 1));
        }
        if !ron {
            situational.push(("tsumo", 1));
        }
    }
    for name in if ron {
        ["houtei", "chankan"]
    } else {
        ["haitei", "rinshan"]
    } {
        if req.flag(name) {
            situational.push((name, 1));
        }
    }
    let owned = counts(req.owned(Some(win)));
    let indicators = |key| -> Result<u64> {
        Ok(tiles(req.get(key, "-"))?
            .into_iter()
            .map(|t| u64::from(owned[kind(t.next())]))
            .sum())
    };
    let dora = indicators("dora")?;
    let ura = if riichi && req.closed() {
        indicators("ura")?
    } else {
        0
    };
    let aka = req.owned(Some(win)).filter(|t| t.is_aka()).count() as u64;
    let payment = |base: i64| {
        let round_up = |n: i64| (n + 99) / 100 * 100;
        if ron {
            let n = round_up(base * if dealer { 6 } else { 4 }) + 300 * honba;
            (n, format!("ron:{n}"))
        } else if dealer {
            let n = round_up(base * 2) + 100 * honba;
            (n * 3, format!("all:{n}"))
        } else {
            let ko = round_up(base) + 100 * honba;
            let oya = round_up(base * 2) + 100 * honba;
            (ko * 2 + oya, format!("tsumo:{ko}/{oya}"))
        }
    };
    let names = |mut yaku: Vec<(&str, u64)>| {
        yaku.sort_unstable();
        yaku.into_iter()
            .map(|(name, n)| format!("{name}:{n}"))
            .collect::<Vec<_>>()
            .join(",")
    };
    let mut best = None;
    for mut result in outcomes {
        if !ron && req.closed() {
            let name = if dealer { "tenhou" } else { "chiihou" };
            if req.flag(name) {
                result.yakuman.push((name, 1));
            }
        }
        let (order, response) = if !result.yakuman.is_empty() {
            let n: u8 = result.yakuman.iter().map(|&(_, n)| n).sum();
            let (total, pay) = payment(8000 * i64::from(n));
            let yaku = names(
                result
                    .yakuman
                    .into_iter()
                    .map(|(name, n)| (name, u64::from(n)))
                    .collect(),
            );
            (
                (total, true, 0, 0, Reverse(yaku.clone())),
                format!("yaku={yaku} yakuman={n} pay={pay} total={total}"),
            )
        } else {
            result.yaku.extend(situational.iter().copied());
            if result.yaku.is_empty() {
                continue;
            }
            let mut yaku: Vec<_> = result
                .yaku
                .into_iter()
                .map(|(name, n)| (name, u64::from(n)))
                .collect();
            yaku.extend(
                [("dora", dora), ("aka", aka), ("ura", ura)]
                    .into_iter()
                    .filter(|&(_, n)| n > 0),
            );
            let han: u64 = yaku.iter().map(|&(_, n)| n).sum();
            let fu = result.fu;
            let base = match han {
                13.. => 8000,
                11..=12 => 6000,
                8..=10 => 4000,
                6..=7 => 3000,
                5 => 2000,
                _ => (i64::from(fu) << (han + 2)).min(2000),
            };
            let (total, pay) = payment(base);
            let yaku = names(yaku);
            (
                (total, false, han, fu, Reverse(yaku.clone())),
                format!("yaku={yaku} han={han} fu={fu} pay={pay} total={total}"),
            )
        };
        if best.as_ref().is_none_or(|(old, _)| order > *old) {
            best = Some((order, response));
        }
    }
    best.map(|(_, response)| response).ok_or("no_yaku")
}
