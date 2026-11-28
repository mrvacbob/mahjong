use crate::{Difference, Row};
use anyhow::{Context, Result, ensure};
use riichi::{
    arena::{Board, Poll},
    mjai::{Event, EventExt},
    state::PlayerState,
    tile::Tile,
};
use serde_json::{Value, json};
use std::{array, io::Write};

const UNKNOWN: usize = 37;

fn deal_indices(offset: usize) -> impl Iterator<Item = usize> {
    (0..3)
        .flat_map(move |pass| (0..4).map(move |i| pass * 16 + offset * 4 + i))
        .chain(std::iter::once(48 + offset))
}

pub fn wall_for(board: &Board) -> Vec<Tile> {
    let mut deal = vec![Tile::default(); 52];
    for offset in 0..4 {
        let seat = (board.kyoku as usize + offset) % 4;
        for (index, tile) in deal_indices(offset).zip(board.haipai[seat]) {
            deal[index] = tile;
        }
    }
    deal.into_iter()
        .chain(board.yama.iter().rev().copied())
        .chain(board.rinshan.iter().rev().copied())
        .chain(board.dora_indicators.iter().rev().copied())
        .chain(board.ura_indicators.iter().copied())
        .collect()
}

fn board_for(row: &Row) -> Result<Board> {
    let Event::StartKyoku {
        bakaze,
        kyoku,
        honba,
        kyotaku,
        oya,
        scores,
        ..
    } = row.event
    else {
        anyhow::bail!("expected start_kyoku");
    };
    let wind = bakaze.as_u8();
    ensure!((27..=30).contains(&wind), "invalid round wind");
    ensure!(oya < 4, "invalid dealer");
    ensure!(
        kyotaku <= 251,
        "stick count leaves no room for four declarations"
    );
    ensure!(
        scores
            .iter()
            .all(|&score| (-1_000_000..=1_000_000).contains(&score)),
        "score out of range"
    );
    let wall: Vec<Tile> =
        serde_json::from_value(row.raw["wall"].clone()).context("start_kyoku.wall")?;
    ensure!(wall.len() == 136, "wall must contain 136 tiles");
    let mut counts = [0; UNKNOWN + 1];
    for tile in &wall {
        counts[tile.as_usize()] += 1;
    }
    for (id, count) in counts.into_iter().enumerate() {
        let expected = match id {
            4 | 13 | 22 => 3,
            34..=36 => 1,
            UNKNOWN => 0,
            _ => 4,
        };
        ensure!(
            count == expected,
            "wall contains {count} copies of {}, expected {expected}",
            Tile::try_from(id)?
        );
    }
    Ok(Board {
        kyoku: (wind - 27) * 4 + kyoku - 1,
        honba,
        kyotaku,
        scores,
        haipai: array::from_fn(|seat| {
            let offset = (seat + 4 - oya as usize) % 4;
            let mut indices = deal_indices(offset);
            array::from_fn(|_| wall[indices.next().unwrap()])
        }),
        yama: wall[52..122].iter().rev().copied().collect(),
        rinshan: wall[122..126].iter().rev().copied().collect(),
        dora_indicators: wall[126..131].iter().rev().copied().collect(),
        ura_indicators: wall[131..136].to_vec(),
    })
}

fn sorted<const N: usize>(tiles: &mut [Tile; N]) {
    tiles.sort_unstable_by_key(|tile| tile.as_u8());
}

fn canonical(mut event: Event) -> Event {
    match &mut event {
        Event::StartKyoku { tehais, .. } => tehais.iter_mut().for_each(sorted),
        Event::Chi { consumed, .. } | Event::Pon { consumed, .. } => sorted(consumed),
        Event::Kakan { consumed, .. } | Event::Daiminkan { consumed, .. } => sorted(consumed),
        Event::Ankan { consumed, .. } => sorted(consumed),
        _ => {}
    }
    event
}

fn mismatch(index: usize, row: Option<&Row>, expected: Value) -> Difference {
    Difference {
        index,
        seat: row.and_then(|row| row.event.actor()).or_else(|| {
            expected["actor"]
                .as_u64()
                .and_then(|actor| u8::try_from(actor).ok())
        }),
        log: row.map_or(Value::Null, |row| row.raw.clone()),
        libriichi: expected,
    }
}

fn check_field(index: usize, row: &Row, key: &str, expected: Value) -> Result<(), Difference> {
    if let Some(actual) = row.raw.get(key) {
        if actual != &expected {
            return Err(Difference {
                index,
                seat: row.event.actor(),
                log: json!({key: actual}),
                libriichi: json!({key: expected}),
            });
        }
    }
    Ok(())
}

fn check_consumed(state: &PlayerState, consumed: &[Tile]) -> Result<()> {
    let mut counts = state.tehai();
    let mut reds = state.akas_in_hand();
    for &tile in consumed {
        let id = tile.deaka().as_usize();
        ensure!(id < 34, "masked tile in action");
        if tile.is_aka() {
            let suit = tile.as_usize() - 34;
            ensure!(reds[suit], "missing consumed red tile");
            reds[suit] = false;
        } else if matches!(id, 4 | 13 | 22) {
            ensure!(counts[id] > u8::from(reds[id / 9]), "missing ordinary five");
        }
        ensure!(counts[id] > 0, "missing tile {tile}");
        counts[id] -= 1;
    }
    Ok(())
}

// Supplement arena validation where it trusts the agent's tile payload.
fn validate(states: &[PlayerState; 4], previous: &[EventExt], event: &Event) -> Result<()> {
    let Some(actor) = event.actor() else {
        return Ok(());
    };
    let state = &states[actor as usize];
    let cans = state.last_cans();
    match *event {
        Event::Dahai { pai, tsumogiri, .. } => {
            ensure!(
                cans.can_discard
                    && pai.as_usize() < UNKNOWN
                    && state.discard_candidates_aka()[pai.as_usize()],
                "discard is outside libriichi candidates"
            );
            if state.self_riichi_accepted() {
                ensure!(tsumogiri, "accepted riichi requires tsumogiri");
            }
            if !tsumogiri && state.last_self_tsumo() == Some(pai) {
                check_consumed(state, &[pai, pai])?;
            }
        }
        Event::Chi {
            target,
            pai,
            consumed,
            ..
        } => {
            ensure!(
                target == cans.target_actor && pai.as_usize() < UNKNOWN,
                "wrong call target or tile"
            );
            check_consumed(state, &consumed)?;
            let mut ids = [pai, consumed[0], consumed[1]].map(|tile| tile.deaka().as_usize());
            ids.sort_unstable();
            ensure!(
                ids[2] < 27
                    && ids[0] / 9 == ids[2] / 9
                    && ids[0] + 1 == ids[1]
                    && ids[1] + 1 == ids[2],
                "invalid chi sequence"
            );
        }
        Event::Pon {
            target,
            pai,
            consumed,
            ..
        } => {
            ensure!(
                target == cans.target_actor
                    && consumed.iter().all(|tile| tile.deaka() == pai.deaka()),
                "invalid pon target or tiles"
            );
            check_consumed(state, &consumed)?;
        }
        Event::Daiminkan {
            target,
            pai,
            consumed,
            ..
        } => {
            ensure!(
                target == cans.target_actor
                    && consumed.iter().all(|tile| tile.deaka() == pai.deaka()),
                "invalid daiminkan target or tiles"
            );
            check_consumed(state, &consumed)?;
        }
        Event::Ankan { consumed, .. } => {
            ensure!(
                consumed
                    .iter()
                    .all(|tile| tile.deaka() == consumed[0].deaka()),
                "invalid ankan tiles"
            );
            check_consumed(state, &consumed)?;
        }
        Event::Kakan {
            pai, mut consumed, ..
        } => {
            check_consumed(state, &[pai])?;
            sorted(&mut consumed);
            ensure!(
                previous.iter().any(|row| {
                    if let Event::Pon {
                        actor: caller,
                        pai: called,
                        consumed: used,
                        ..
                    } = row.event
                    {
                        let mut pon = [called, used[0], used[1]];
                        sorted(&mut pon);
                        caller == actor && pai.deaka() == called.deaka() && pon == consumed
                    } else {
                        false
                    }
                }),
                "kakan consumed tiles do not match original pon"
            );
        }
        Event::Hora { target, .. } => {
            ensure!(target == cans.target_actor, "wrong hora target");
        }
        _ => {}
    }
    state.validate_reaction(event)
}

fn choose(
    rows: &[Row],
    start: usize,
    states: &[PlayerState; 4],
    previous: &[EventExt],
) -> Result<[EventExt; 4], Difference> {
    let mut reactions: [EventExt; 4] = Default::default();
    let mut pending = rows.iter().enumerate().skip(start).skip_while(|(_, row)| {
        matches!(row.event, Event::ReachAccepted { .. } | Event::Dora { .. })
    });
    let Some((index, row)) = pending.next() else {
        return Ok(reactions);
    };
    let actions = match row.event {
        Event::Ryukyoku { .. } => {
            if let Some((seat, _)) = states
                .iter()
                .enumerate()
                .find(|(_, state)| state.last_cans().can_ryukyoku)
            {
                reactions[seat] = Event::Ryukyoku { deltas: None }.into();
            }
            return Ok(reactions);
        }
        Event::Hora { .. } => {
            let mut actions = vec![(index, row)];
            actions.extend(pending.take_while(|(_, row)| matches!(row.event, Event::Hora { .. })));
            actions
        }
        Event::Dahai { .. }
        | Event::Chi { .. }
        | Event::Pon { .. }
        | Event::Ankan { .. }
        | Event::Daiminkan { .. }
        | Event::Kakan { .. }
        | Event::Reach { .. } => vec![(index, row)],
        _ => return Ok(reactions),
    };
    for (index, row) in actions {
        let actor = row.event.actor().unwrap() as usize;
        if reactions[actor].event != Event::None {
            return Err(mismatch(index, Some(row), json!("duplicate winner")));
        }
        validate(states, previous, &row.event).map_err(|error| {
            mismatch(
                index,
                Some(row),
                json!({"rejected_action": format!("{error:#}"),
                "flags": states[actor].last_cans()}),
            )
        })?;
        reactions[actor] = row.event.clone().into();
    }
    Ok(reactions)
}

pub fn replay(
    rows: &[Row],
    next: Option<&Row>,
    filtered: &mut std::collections::BTreeMap<&'static str, usize>,
) -> Result<(), Difference> {
    let board = board_for(&rows[0])
        .map_err(|error| mismatch(0, rows.first(), json!(format!("{error:#}"))))?;
    let mut scores = board.scores;
    let mut sticks = board.kyotaku;
    let mut winning_tile = None;
    let mut accepted = 0;
    let mut state = board.into_state();
    let mut compared = 0;
    let mut generated = 0;
    let mut reactions = Default::default();
    loop {
        let poll = state.poll(reactions).map_err(|error| {
            mismatch(
                compared,
                rows.get(compared),
                json!({"arena_error": format!("{error:#}")}),
            )
        })?;
        let context = state.agent_context();
        for (arena_index, entry) in context.log.iter().enumerate().skip(generated) {
            let index = compared;
            let expected = &entry.event;
            let row = rows
                .get(index)
                .ok_or_else(|| mismatch(index, None, json!(expected)))?;
            if accepted == 4
                && matches!(expected, Event::Tsumo { .. })
                && matches!(
                    row.event,
                    Event::Ryukyoku {
                        deltas: Some([0, 0, 0, 0])
                    }
                )
                && matches!(
                    context.log[arena_index - 1].event,
                    Event::ReachAccepted { .. }
                )
            {
                *filtered.entry("four_riichi_extra_draw").or_default() += 1;
                continue;
            }
            if canonical(row.event.clone()) != canonical(expected.clone()) {
                return Err(mismatch(index, Some(row), json!(expected)));
            }
            if &row.event != expected {
                let name = if index == 0 {
                    "deal_tile_order"
                } else {
                    "consumed_tile_order"
                };
                *filtered.entry(name).or_default() += 1;
            }
            match *expected {
                Event::ReachAccepted { actor } => {
                    scores[actor as usize] -= 1000;
                    sticks += 1;
                    accepted += 1;
                    check_field(index, row, "scores", json!(scores))?;
                }
                Event::Hora {
                    deltas: Some(deltas),
                    ref ura_markers,
                    ..
                } => {
                    check_field(index, row, "pai", json!(winning_tile))?;
                    check_field(index, row, "uradora_markers", json!(ura_markers))?;
                    for (score, delta) in scores.iter_mut().zip(deltas) {
                        *score += delta;
                    }
                    check_field(index, row, "scores", json!(scores))?;
                    sticks = 0;
                }
                Event::Ryukyoku {
                    deltas: Some(deltas),
                } => {
                    for (score, delta) in scores.iter_mut().zip(deltas) {
                        *score += delta;
                    }
                    check_field(index, row, "scores", json!(scores))?;
                }
                Event::Tsumo { pai, .. } | Event::Dahai { pai, .. } | Event::Kakan { pai, .. } => {
                    winning_tile = Some(pai);
                }
                _ => {}
            }
            compared += 1;
        }
        generated = context.log.len();
        if matches!(poll, Poll::End) {
            break;
        }
        if compared >= rows.len() {
            return Err(mismatch(
                compared,
                None,
                json!("expected next action or event"),
            ));
        }
        if accepted == 4 {
            reactions = Default::default();
            continue;
        }
        reactions = choose(rows, compared, context.player_states, context.log)?;
        // A required discard cannot be replaced by a pass.
        if let Some((seat, _)) = context
            .player_states
            .iter()
            .enumerate()
            .find(|(seat, state)| {
                state.last_cans().can_discard && reactions[*seat].event == Event::None
            })
        {
            let mut diff = mismatch(
                compared,
                rows.get(compared),
                json!("seat must act after draw, call, or reach"),
            );
            diff.seat = Some(seat as u8);
            return Err(diff);
        }
    }

    if rows.len() != compared {
        return Err(mismatch(compared, rows.get(compared), Value::Null));
    }
    let result = state.end();
    let index = compared - 1;
    let end = &rows[index];
    check_field(index, end, "scores", json!(result.scores))?;
    check_field(index, end, "kyotaku_left", json!(result.kyotaku_left))?;
    check_field(index, end, "dealer_repeats", json!(result.can_renchan))?;
    let Event::StartKyoku {
        scores: initial,
        honba,
        ..
    } = rows[0].event
    else {
        unreachable!()
    };
    check_field(
        index,
        end,
        "deltas",
        json!(array::from_fn::<_, 4, _>(
            |seat| scores[seat] - initial[seat]
        )),
    )?;
    if (scores, sticks) != (result.scores, result.kyotaku_left) {
        return Err(Difference {
            index,
            seat: None,
            log: json!({"scores": scores, "kyotaku_left": sticks}),
            libriichi: json!({"scores": result.scores, "kyotaku_left": result.kyotaku_left}),
        });
    }
    if let Some(next) = next {
        let kyoku = result.kyoku + u8::from(!result.can_renchan);
        let next_honba = if result.has_hora && !result.can_renchan {
            0
        } else {
            u16::from(honba) + 1
        };
        let expected = json!({"scores": result.scores, "kyotaku": result.kyotaku_left, "honba": next_honba,
            "oya": kyoku % 4, "kyoku": kyoku % 4 + 1, "bakaze": Tile::try_from(27 + kyoku / 4).unwrap()});
        for field in ["scores", "kyotaku", "honba", "oya", "kyoku", "bakaze"] {
            check_field(compared, next, field, expected[field].clone())?;
        }
    }
    Ok(())
}

fn tiles(flags: &[bool]) -> Vec<Tile> {
    flags
        .iter()
        .enumerate()
        .filter(|(_, enabled)| **enabled)
        .map(|(id, _)| Tile::try_from(id).unwrap())
        .collect()
}

pub fn emit_states(
    file: &str,
    hand: usize,
    rows: &[Row],
    output: &mut impl Write,
    total: &mut usize,
) -> Result<Option<Difference>> {
    let mut states: [PlayerState; 4] = array::from_fn(|seat| PlayerState::new(seat as u8));
    let unknown = Tile::try_from(UNKNOWN)?;
    let mut seen = [[0; 34]; 4];
    for (index, row) in rows.iter().enumerate() {
        for (seat, state) in states.iter_mut().enumerate() {
            let mut masked = row.event.clone();
            match &mut masked {
                Event::StartKyoku { tehais, .. } => {
                    for (owner, tiles) in tehais.iter_mut().enumerate() {
                        if owner != seat {
                            tiles.fill(unknown);
                        }
                    }
                }
                Event::Tsumo { actor, pai } if *actor as usize != seat => *pai = unknown,
                _ => {}
            }
            let seen = &mut seen[seat];
            let mut witness = |tile: Tile| seen[tile.deaka().as_usize()] += 1;
            match &masked {
                Event::StartKyoku {
                    tehais,
                    dora_marker,
                    ..
                } => {
                    tehais[seat].iter().copied().for_each(&mut witness);
                    witness(*dora_marker);
                }
                Event::Tsumo { actor, pai } if *actor as usize == seat => witness(*pai),
                Event::Dahai { actor, pai, .. } | Event::Kakan { actor, pai, .. }
                    if *actor as usize != seat =>
                {
                    witness(*pai)
                }
                Event::Chi {
                    actor, consumed, ..
                }
                | Event::Pon {
                    actor, consumed, ..
                } if *actor as usize != seat => consumed.iter().copied().for_each(&mut witness),
                Event::Daiminkan {
                    actor, consumed, ..
                } if *actor as usize != seat => consumed.iter().copied().for_each(&mut witness),
                Event::Ankan {
                    actor, consumed, ..
                } if *actor as usize != seat => consumed.iter().copied().for_each(&mut witness),
                Event::Dora { dora_marker } => witness(*dora_marker),
                _ => {}
            }
            let flags = match state.update(&masked) {
                Ok(flags) => flags,
                Err(error) => {
                    let mut diff = mismatch(
                        index,
                        Some(row),
                        json!({"player_state_error": format!("{error:#}")}),
                    );
                    diff.seat = Some(seat as u8);
                    return Ok(Some(diff));
                }
            };
            let discard = if flags.can_discard {
                tiles(&state.discard_candidates_aka())
            } else {
                vec![]
            };
            serde_json::to_writer(
                &mut *output,
                &json!({
                    "file": file, "hand": hand, "event_index": index, "seat": seat,
                    "event_type": row.raw["type"], "flags": flags, "discard": discard,
                    "ankan": state.ankan_candidates(), "kakan": state.kakan_candidates(),
                    "waits": tiles(&state.waits()), "shanten": state.real_time_shanten(),
                    "visible_exhausted": tiles(&seen.map(|n| n == 4)),
                    "furiten": state.at_furiten(),
                }),
            )?;
            writeln!(output)?;
            *total += 1;
        }
    }
    Ok(None)
}
