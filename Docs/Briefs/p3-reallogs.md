# Brief: real-log campaign

Real game records in mjai form are at `/Volumes/Psyche/mahjong/logs/` (also
reachable as `../data/logs`; read its `README.md`). Each `*.tar` holds one
`.mjai.json.zst` per game: `tenhou-mjai/tenhou-houou-YEAR.tar` (Tenhou top room,
2009–2026, ~3M games) and `majsoul-mjai/majsoul-{jade,throne}-YEAR.tar` (Mahjong
Soul ranked, 2019–2026). **These files are third-party records: never copy any of
them, or excerpts beyond a few lines needed to describe a bug, into the repository,
and strip player names from anything you quote.** Work in a scratch directory
outside the repo (for example under `/Volumes/Psyche/mahjong/work/`).

A first pass of `mj check-log` over 300 games from each site (2024) matched every
point change. The only differences were conventions of the converter that produced
the logs: `ura_markers` present on every winner of a multi-ron when any winner was
in riichi (6 and 5 cases), and, in Mahjong Soul logs, `dora` before `dahai` after an
open or added kan (120 cases) where our Mahjong Soul default emits it after.

Goals, in order:

1. **Make `check-log` fit for bulk use.** Read `.zst` and tar members directly or
   via a wrapper script (no third-party Swift packages; shelling out to `zstd`/`tar`
   from a Python driver in `Tools/` is fine), run in parallel across cores, and
   emit a machine-readable difference list plus a summary by category. Treat the
   two converter conventions above as named, counted categories, not errors. Report
   throughput.
2. **Run it wide**: at least all of Tenhou 2023–2025 under `--rules tenhou` and all
   Mahjong Soul throne and jade 2023–2025 under Mahjong Soul rules; more years if
   time allows (older Tenhou years may predate rule changes listed in the Tenhou
   manual, e.g. 2007–2010; note what you see). Every difference that is not a named
   convention gets classified: engine bug (fix it, add a test, re-run), log or
   converter defect (describe), or rule difference (see 3). Zero unexplained
   differences is the target.
3. **Settle the unverified rulings from evidence.** `Spec/rules.md` §5 and
   `Docs/Design/engine.md` §10 list rulings never checked against a real client.
   Point changes in real Mahjong Soul games can decide several. For each, find the
   hands in the logs that discriminate, and report counts for and against:
   - kan dora on a ron of the discard right after an open or added kan (does the
     payment include the new indicator, and its ura?), and on a rinshan win;
   - multi-ron: who receives honba and sticks; triple ron paying three winners;
   - pao: composite yakuman, who pays honba, ron from a third party;
   - a riichi declared on a ronned discard (no stick), on a fourth-wind abort, and
     four-riichi and four-kan abort timing;
   - nagashi mangan payments, honba and sticks, and dealer repeat;
   - end of game: all-last finish, extension, dealer repeat against the 30,000
     finish, leftover sticks;
   - formal tenpai on a fifth-copy wait at an exhaustive draw;
   - anything else where the two rulesets or the design's defaults could differ
     and the logs can tell.
   Add an option to `check-log` to override individual `Rules` fields
   (`--set field=value`) so each hypothesis can be run both ways. Where the
   evidence is clear, change the `Rules.mahjongSoul` (or `.tenhou`) default, update
   the `rules.md` row and its §5 item with the evidence (counts and a log id, no
   player names), and say which scenarios in `Scenarios/` now have the wrong
   expectation (do not edit `.scn` files; list them).
4. **Frequency table** for the roadmap's coverage question: over the games you ran,
   how often each rare situation occurs per million hands (each abort, chankan,
   rinshan win, closed kan in riichi, double and triple ron, pao, nagashi, four kans
   by one seat, kyuushu, each yakuman).

Constraints: corpus 12,439 of 12,439 and `swift test` green at the end; no
Foundation in `Riichi` or `RiichiMjai`; do not edit `AGPL/` or `.scn` files; do not
commit. Write `Docs/Notes/p3-reallogs.md` with the numbers, every engine bug found,
every ruling settled with its evidence, and what could not be decided.
