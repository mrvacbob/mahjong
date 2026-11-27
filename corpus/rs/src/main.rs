#![allow(clippy::manual_range_patterns)] // Match tile names through libriichi macros.

mod algo;
mod macros;
mod model;
mod scoring;
mod shape;
mod state;
#[allow(dead_code)]
mod tile;

use crate::model::{Request, Result, counts, notation, shantens, tile};
use std::io::{self, BufRead, Write};

fn answer(op: &str, request: &Request<'_>) -> Result<String> {
    let hand = counts(request.hand.iter().copied());
    let groups = request.groups();
    match op {
        "shanten" => {
            request.check_size(0).or_else(|_| request.check_size(1))?;
            let (standard, pairs, orphans, min) = shantens(&hand, groups);
            let show = |value: Option<i8>| value.map_or("x".into(), |n| n.to_string());
            Ok(format!(
                "std={standard} chiitoi={} kokushi={} min={min}",
                show(pairs),
                show(orphans)
            ))
        }
        "waits" => {
            request.check_size(0)?;
            let owned = counts(request.owned(None));
            let shanten = shantens(&hand, groups).3;
            let mut waits = Vec::new();
            let mut count = 0;
            for (i, &owned) in owned.iter().enumerate() {
                if owned == 4 {
                    continue;
                }
                let mut after = hand;
                after[i] += 1;
                if shantens(&after, groups).3 < shanten {
                    waits.push(tile(i as u8));
                    count += 4 - owned;
                }
            }
            Ok(format!(
                "shanten={shanten} tiles={} count={count}",
                notation(&waits)
            ))
        }
        "agari" => {
            request.check_size(1)?;
            let (kokushi, chiitoi, forms) = algo::agari::forms(&hand);
            let mut rendered = Vec::new();
            if kokushi {
                rendered.push("kokushi".to_string());
            }
            if chiitoi {
                rendered.push("chiitoi".to_string());
            }
            for form in forms {
                rendered.push(
                    form.into_iter()
                        .map(|(id, group)| {
                            let tiles = match group {
                                0 => vec![tile(id); 2],
                                1 => (id..=id + 2).map(tile).collect(),
                                _ => vec![tile(id); 3],
                            };
                            notation(&tiles)
                        })
                        .collect::<Vec<_>>()
                        .join(","),
                );
            }
            rendered.sort_unstable();
            rendered.dedup();
            if rendered.is_empty() {
                Ok("win=0".into())
            } else {
                Ok(format!("win=1 forms={}", rendered.join(";")))
            }
        }
        "score" => scoring::score(request),
        "legal" => state::legal(request),
        _ => Err("unknown_op"),
    }
}

fn main() -> io::Result<()> {
    algo::shanten::ensure_init();
    let mut stdout = io::BufWriter::new(io::stdout().lock());
    let mut stdin = io::stdin().lock();
    let mut bytes = Vec::new();
    loop {
        bytes.clear();
        if stdin.read_until(b'\n', &mut bytes)? == 0 {
            break;
        }
        let line = match std::str::from_utf8(&bytes) {
            Ok(line) => line,
            Err(_) => {
                let first = bytes
                    .split(|b| b.is_ascii_whitespace())
                    .next()
                    .unwrap_or_default();
                let id = std::str::from_utf8(first)
                    .ok()
                    .filter(|id| !id.is_empty())
                    .unwrap_or("-");
                writeln!(stdout, "{id} error=bad_encoding")?;
                stdout.flush()?;
                continue;
            }
        };
        let mut parts = line.split_whitespace();
        let id = parts.next().unwrap_or("-");
        let result = parts
            .next()
            .ok_or("missing_op")
            .and_then(|op| Request::parse(parts).and_then(|request| answer(op, &request)));
        match result {
            Ok(response) => writeln!(stdout, "{id} {response}")?,
            Err(reason) => writeln!(stdout, "{id} error={reason}")?,
        }
        stdout.flush()?;
    }
    Ok(())
}
