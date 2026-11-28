use crate::replay::wall_for;
use anyhow::{Result, ensure};
use riichi::{
    agent::{Agent, Tsumogiri},
    arena::{Board, Poll},
    mjai::{Event, EventExt},
    tile::Tile,
};
use serde_json::json;
use std::{
    array,
    fs::{self, File},
    io::{BufWriter, Write},
    path::Path,
};

fn write(output: &mut impl Write, row: serde_json::Value) -> Result<()> {
    serde_json::to_writer(&mut *output, &row)?;
    writeln!(output)?;
    Ok(())
}

pub fn generate(games: u64, directory: &Path) -> Result<()> {
    ensure!(games > 0, "generate requires a positive game count");
    fs::create_dir_all(directory)?;
    for game in 0..games {
        let mut output = BufWriter::new(File::create(
            directory.join(format!("game-{game:04}.jsonl")),
        )?);
        write(
            &mut output,
            json!({"type": "start_game", "names": (["tsumogiri"; 4])}),
        )?;
        let mut kyoku = 0;
        let mut honba = 0;
        let mut kyotaku = 0;
        let mut scores = [25000; 4];
        // East-only schedule with a South extension, as in arena::Game.
        loop {
            let mut board = Board {
                kyoku,
                honba,
                kyotaku,
                scores,
                ..Default::default()
            };
            board.init_from_seed((game, 0));
            let (next_scores, next_sticks, repeats, won, abort) = play(&mut output, board, false)?;
            scores = next_scores;
            kyotaku = next_sticks;
            if scores.iter().any(|&score| score < 0) {
                break;
            }
            let leader = (0..4).max_by_key(|&seat| (scores[seat], 3 - seat)).unwrap();
            if repeats {
                if !abort && kyoku >= 3 && leader == kyoku as usize % 4 && scores[leader] >= 30000 {
                    break;
                }
            } else {
                kyoku += 1;
                if kyoku == 8 || (kyoku >= 4 && scores[leader] >= 30000) {
                    break;
                }
            }
            honba = if won && !repeats { 0 } else { honba + 1 };
        }
        write(&mut output, json!({"type": "end_game"}))?;
        output.flush()?;
    }
    // Force a first-draw closed kan in one legal seeded board so the dora
    // corruption is exercised even when all the built-in agents only discard.
    let mut output = BufWriter::new(File::create(directory.join("kan.jsonl"))?);
    let board = (0..10_000)
        .find_map(|seed| {
            let mut board = Board {
                scores: [25000; 4],
                ..Default::default()
            };
            board.init_from_seed((seed, 1));
            let mut counts = [0; 34];
            for tile in board.haipai[0].iter().chain(board.yama.last()) {
                counts[tile.deaka().as_usize()] += 1;
            }
            counts.contains(&4).then_some(board)
        })
        .expect("seed search should find an opening quad");
    play(&mut output, board, true)?;
    output.flush()?;
    eprintln!("generated {games} arena games and one closed-kan hand");
    Ok(())
}

fn play(
    output: &mut impl Write,
    board: Board,
    opening_kan: bool,
) -> Result<([i32; 4], u8, bool, bool, bool)> {
    let wall = wall_for(&board);
    let initial_scores = board.scores;
    let mut state = board.into_state();
    let mut agents: [Tsumogiri; 4] = array::from_fn(|seat| Tsumogiri(seat as u8));
    let mut reactions: [EventExt; 4] = Default::default();
    let mut first = true;
    while matches!(state.poll(reactions)?, Poll::InGame) {
        let context = state.agent_context();
        reactions = Default::default();
        for (seat, (agent, player)) in agents.iter_mut().zip(context.player_states).enumerate() {
            reactions[seat] = agent.react(context.log, player, None)?;
        }
        if first && opening_kan {
            let dealer = &context.player_states[0];
            let kind = dealer.ankan_candidates()[0];
            let mut consumed = [kind; 4];
            if matches!(kind.as_usize(), 4 | 13 | 22) {
                consumed[0] = Tile::try_from(34 + kind.as_usize() / 9)?;
            }
            reactions[0] = Event::Ankan { actor: 0, consumed }.into();
        }
        first = false;
    }
    let result = state.end();
    for entry in state.take_log() {
        let mut row = serde_json::to_value(&entry.event)?;
        match entry.event {
            Event::StartKyoku { .. } => row["wall"] = json!(wall),
            Event::EndKyoku => {
                row["scores"] = json!(result.scores);
                row["deltas"] = json!(array::from_fn::<_, 4, _>(
                    |seat| result.scores[seat] - initial_scores[seat]
                ));
                row["kyotaku_left"] = json!(result.kyotaku_left);
                row["dealer_repeats"] = json!(result.can_renchan);
            }
            _ => {}
        }
        write(output, row)?;
    }
    Ok((
        result.scores,
        result.kyotaku_left,
        result.can_renchan,
        result.has_hora,
        result.has_abortive_ryukyoku,
    ))
}
