# mj-rs build and corpus notes

## Build and run

Run these commands from the repository root with Rust, Cargo and `gzip` installed.

```sh
CARGO_HOME="$PWD/AGPL/mj-rs/.cargo-cache" cargo build --offline --locked --release --manifest-path AGPL/mj-rs/Cargo.toml
printf '%s\n' 'demo waits hand=1122334455667m' | AGPL/mj-rs/target/release/mj-rs
python3.14 -B Tools/harness.py AGPL/mj-rs/target/release/mj-rs AGPL/mj-rs/smoke.txt Corpus/legal.txt
python3.14 -B AGPL/mj-rs/compare.py
```

The runner uses only the standard library and embeds the vendor tables; the build script expands the checked-in gzip files inside Cargo's output directory. Because upstream libriichi declares PyO3 and NumPy as unconditional dependencies and has no constructor for arbitrary snapshots, this offline crate vendors only libriichi's shanten and agari tables, algorithms, and chi decision flags, omitting the full mjai event processor, Python bridge, and learned-agent state. The snapshot adapter ports the relevant `PlayerState` draw, discard, kan, and kuikae decisions. `prepare_vendor.py` documents the mechanical transformations. The vendored source is covered by [Mortal's license](LICENSE.libriichi).

## Score and shape decisions

- Use the Mahjong Soul ranked defaults in `Spec/rules.md`. The four natural variants `kokushi_13`, `suuankou_tanki`, `daisuushii` and `junsei_chuuren` count double. The seat/round wind pair gives four fu. Natural yakuman stack. For explicit `tenhou`/`chiihou`, stack with compatible natural yakuman under that rule. Libriichi's game state returns a single yakuman for its first-draw special before pattern scoring.
- Libriichi normally returns aggregate han and fu and can skip fu on limit hands. The adapted evaluator records each yaku and computes fu for every ordinary answer. It evaluates each winning placement and sorts by total, han and fu. A natural yakuman takes an equal-payment tie with an ordinary hand. Remaining ties go to the lexicographically first yaku list. Tenhou checks every distinct winning kind in the opening hand. Chiihou uses the supplied winning tile.
- Kazoe pays one yakuman at 13 or more han. The response preserves the ordinary yaku, han and fu because the format defines no counted-yakuman name. Indicators multiply, including when they repeat. Ura applies only after riichi or double riichi. Dora cannot supply the first yaku.
- The score input lacks meld caller identities and resolution order. Its single-winner payout follows the supplied honba and the format's payment split. Pao, other simultaneous winners and riichi sticks are outside this interface.
- Libriichi's table can omit the seven-pairs entry when a standard form exists. The adapter checks that form independently and enumerates additional valid standard divisions after the table match. For example, libriichi omits `555p,678p,678p,678p,99p` for `55566677788899p`. Agari groups sort by suit, first digit and group type, following the written rule where the example gives a different order.
- Shanten computes each shape directly. For concealed quads, the structural standard-shanten fallback permits an abstract fifth copy in an incomplete shape. Libriichi’s table excludes that shape. Waits then applies the four-copy filter to the hand and all declared melds, then counts all remaining physical copies of qualifying kinds. Tiles visible outside that ownership do not enter the count. The physical input accepts up to three ordinary fives plus one red per suit.

## Legal decisions

- `wall` limits calls, kans and riichi. Haitei, houtei, rinshan, tenhou and chiihou are supplied as flags. The `first` field enables kyuushu. A `chankan` or `ankan_rob` response offers pass and, when legal, ron. Closed-kan robbery requires kokushi.
- A riichi ankan uses the drawn tile and preserves the set of structural wait kinds. The check compares the concealed shape before the draw with the concealed shape after fixing the new kan as a meld. It allows decomposition changes and ignores copy availability.
- Riichi declaration requires structural tenpai with a positive wait count after the discard. The remaining copies are counted outside the concealed hand and melds as in `waits`. Furiten blocks ron only.
- A `called` snapshot represents the discard owed after chi or pon. The tile taken must occur in the specified meld, which must also occur in `melds`. Existing kans count toward the hand's meld total. Kuikae operates by kind and bans the taken kind and, on the appropriate chi, the opposite sequence endpoint.

## Corpus provenance and verification

`legal.txt` contains 600 unique snapshots from six Akochan replay hands and 50 directed cases. The seeded sampler spreads the replay selection across event types, available action verbs, flags, riichi, furiten, first draws, discard direction and meld presence. The generator checks the recorded moves across the full replay, and the directed rows specify required and forbidden actions. The full expected action sets come from the Rust evaluator. Independently authored cases are compared separately in [DISAGREEMENTS.md](DISAGREEMENTS.md).

Replay snapshots reconstruct permanent furiten from the seat's own discards and wait kinds. They reconstruct temporary and riichi furiten from passed yaku-bearing wins. Run `python3.14 -B AGPL/mj-rs/generate_legal.py` after building to reproduce the corpus.
