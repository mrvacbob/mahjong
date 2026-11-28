mod replay;
mod self_test;

use anyhow::{Context, Result, bail, ensure};
use riichi::mjai::Event;
use serde_json::{Value, json};
use std::{
    env,
    fs::File,
    io::{self, BufRead, BufReader, Write},
    path::Path,
};

struct Row {
    raw: Value,
    event: Event,
}

impl Row {
    fn parse(line: &str) -> Result<Self> {
        let raw: Value = serde_json::from_str(line)?;
        let event = serde_json::from_value(raw.clone())?;
        Ok(Self { raw, event })
    }
}

#[derive(Debug)]
struct Difference {
    index: usize,
    seat: Option<u8>,
    log: Value,
    libriichi: Value,
}

impl Difference {
    fn print(&self, file: &str, hand: usize) {
        eprintln!(
            "{}",
            json!({
                "file": file, "hand": hand, "event_index": self.index, "seat": self.seat,
                "log": self.log, "libriichi": self.libriichi
            })
        );
    }
}

#[derive(Default)]
struct Totals {
    files: usize,
    hands: usize,
    failed: usize,
    state_rows: usize,
    missing_sticks: usize,
    missing_repeat: usize,
    filtered: std::collections::BTreeMap<&'static str, usize>,
}

fn check_file(
    file: &str,
    input: impl BufRead,
    output: &mut impl Write,
    totals: &mut Totals,
) -> Result<()> {
    let mut rows = Vec::new();
    let mut hand = 0;
    let mut game_ended = false;
    let mut bad_hand = false;
    for line in input.lines() {
        let line = line?;
        let parsed = Row::parse(&line);
        let kind = parsed.as_ref().map_or_else(
            |_| {
                serde_json::from_str::<Value>(&line)
                    .ok()
                    .and_then(|v| v["type"].as_str().map(str::to_owned))
            },
            |row| row.raw["type"].as_str().map(str::to_owned),
        );
        if matches!(
            kind.as_deref(),
            Some("start_kyoku" | "start_game" | "end_game")
        ) && !rows.is_empty()
        {
            check_hand(
                file,
                hand,
                &rows,
                kind.as_deref()
                    .filter(|&k| k == "start_kyoku")
                    .and_then(|_| parsed.as_ref().ok()),
                output,
                totals,
            )?;
            rows.clear();
        }
        match kind.as_deref() {
            Some("start_kyoku") => {
                hand += 1;
                totals.hands += 1;
                bad_hand = false;
                game_ended = false;
            }
            Some("start_game") => {
                game_ended = false;
                bad_hand = false;
            }
            Some("end_game") => game_ended = true,
            _ => {}
        }
        match parsed {
            Ok(Row {
                event: Event::StartGame { .. } | Event::EndGame,
                ..
            }) => {}
            Ok(row)
                if kind.as_deref() == Some("start_kyoku")
                    || (!rows.is_empty() && !bad_hand && !game_ended) =>
            {
                rows.push(row)
            }
            _ if bad_hand => {}
            other => {
                let index = rows.len();
                rows.clear();
                bad_hand = true;
                totals.failed += 1;
                Difference {
                    index,
                    seat: None,
                    log: other
                        .as_ref()
                        .map_or_else(|_| json!(line), |row| row.raw.clone()),
                    libriichi: json!(other.err().map_or_else(
                        || "expected start_kyoku".to_owned(),
                        |error| format!("{error:#}"),
                    )),
                }
                .print(file, hand);
            }
        }
    }
    if !rows.is_empty() {
        check_hand(file, hand, &rows, None, output, totals)?;
    }
    ensure!(hand > 0, "{file}: no hands");
    Ok(())
}

fn check_hand(
    file: &str,
    hand: usize,
    rows: &[Row],
    next: Option<&Row>,
    output: &mut impl Write,
    totals: &mut Totals,
) -> Result<()> {
    match replay::replay(rows, next, &mut totals.filtered) {
        Ok(()) => {
            if next.is_none() {
                let end = &rows.last().unwrap().raw;
                totals.missing_sticks += usize::from(end.get("kyotaku_left").is_none());
                totals.missing_repeat += usize::from(end.get("dealer_repeats").is_none());
            }
            match replay::emit_states(file, hand, rows, output, &mut totals.state_rows)? {
                Some(diff) => {
                    diff.print(file, hand);
                    totals.failed += 1;
                }
                None => {}
            }
        }
        Err(diff) => {
            diff.print(file, hand);
            totals.failed += 1;
        }
    }
    Ok(())
}

fn run() -> Result<()> {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("check") => {
            let files: Vec<_> = args.collect();
            ensure!(
                !files.is_empty(),
                "check requires at least one file (or - for stdin)"
            );
            let mut totals = Totals::default();
            let mut output = io::BufWriter::new(io::stdout().lock());
            for file in files {
                totals.files += 1;
                if file == "-" {
                    check_file(&file, io::stdin().lock(), &mut output, &mut totals)?;
                } else {
                    let input = File::open(&file).with_context(|| format!("open {file}"))?;
                    check_file(&file, BufReader::new(input), &mut output, &mut totals)?;
                }
            }
            output.flush()?;
            eprintln!(
                "{}",
                json!({"files": totals.files, "hands": totals.hands,
                "failed": totals.failed, "state_rows": totals.state_rows, "filtered": totals.filtered,
                    "unavailable_final_sticks": totals.missing_sticks,
                    "unavailable_final_dealer_repeat": totals.missing_repeat})
            );
            ensure!(totals.failed == 0, "unexplained divergence");
        }
        Some("generate") => {
            let games = args.next().context("missing game count")?.parse()?;
            let directory = args.next().context("missing output directory")?;
            ensure!(args.next().is_none(), "unexpected argument");
            self_test::generate(games, Path::new(&directory))?;
        }
        _ => bail!("usage: libriichi-check check FILE... | generate GAMES DIRECTORY"),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}
