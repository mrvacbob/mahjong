# mj-rs build and corpus notes

## Build and run

Run these commands from the repository root with Rust, Cargo and `gzip` installed.

```sh
CARGO_HOME="$PWD/corpus/rs/.cargo-cache" cargo build --offline --locked --release --manifest-path corpus/rs/Cargo.toml
printf '%s\n' 'demo waits hand=1122334455667m' | corpus/rs/target/release/mj-rs
python3.14 -B tools/harness.py corpus/rs/target/release/mj-rs corpus/rs/smoke.txt corpus/legal.txt
python3.14 -B corpus/rs/compare.py
```

The runner uses only the standard library and embeds the vendor tables. The build script expands the checked-in gzip files inside Cargo’s output directory. The first build attempt used the Mortal path dependency with default features disabled. Crates.io DNS failed, and this checkout also declares PyO3 and NumPy as unconditional dependencies. The offline crate vendors libriichi's shanten and agari tables and algorithms and its chi decision flags. The snapshot adapter ports the relevant `PlayerState` draw, discard, kan and kuikae decisions. The upstream source does not provide a constructor for arbitrary snapshots. The offline crate omits the full mjai event processor, Python bridge and learned-agent state. `prepare_vendor.py` documents the mechanical transformations. The vendored source is covered by [Mortal's license](LICENSE.libriichi).

## Score and shape decisions

- Use the Mahjong Soul ranked defaults in `spec/rules.md`. The four natural variants `kokushi_13`, `suuankou_tanki`, `daisuushii` and `junsei_chuuren` count double. The seat/round wind pair gives four fu. Natural yakuman stack. For explicit `tenhou`/`chiihou`, stack with compatible natural yakuman under that rule. Libriichi's game state returns a single yakuman for its first-draw special before pattern scoring.
- Libriichi normally returns aggregate han and fu and can skip fu on limit hands. The adapted evaluator records each yaku and computes fu for every ordinary answer. It evaluates each winning placement and sorts by total, han and fu. A natural yakuman takes an equal-payment tie with an ordinary hand. Any remaining tie keeps the first interpretation in the embedded table order.
- Kazoe pays one yakuman at 13 or more han. The response preserves the ordinary yaku, han and fu because the format defines no counted-yakuman name. Indicators multiply, including when they repeat. Ura applies only after riichi or double riichi. Dora cannot supply the first yaku.
- The score input lacks meld caller identities and resolution order. Its single-winner payout follows the supplied honba and the format's payment split. Pao, other simultaneous winners and riichi sticks are outside this interface.
- Libriichi's table can omit the seven-pairs entry when a standard form exists. The adapter checks that form independently and enumerates additional valid standard divisions after the table match. For example, libriichi omits `555p,678p,678p,678p,99p` for `55566677788899p`. Agari groups sort by suit, first digit and group type, following the written rule where the example gives a different order.
- Shanten computes each shape directly. For concealed quads, the structural standard-shanten fallback permits an abstract fifth copy in an incomplete shape. Libriichi’s table excludes that shape. Waits then applies the four-copy filter to the hand and all declared melds, then counts all remaining physical copies of qualifying kinds. Tiles visible outside that ownership do not enter the count. The physical input accepts up to three ordinary fives plus one red per suit.

## Legal decisions

- `wall` is the live-wall count after any incoming draw. Zero infers haitei or houtei for ordinary events. A rinshan draw or chankan response uses its supplied win context. A `chankan` response means an added kan and permits only pass or ron. Kokushi-only robbery of a closed kan needs a discriminator absent from the format.
- For riichi ankan, apply the explicit stricter requirement in `spec/formats.md`. Check every available wait and compare the actual concealed divisions before and after moving the fixed triplet to an ankan. Here “interpretation” means the hand's division into groups. The procedure allows consequences of upgrading a triplet to a kan, such as a change in fu or kan-count yaku. Tenhou's libriichi state uses the waits-only test. The ranked-rule table also lists waits-only and marks the interpretation-changing case unverified.
- Riichi options assume enough points and include karaten. The PlayerState calculation excludes fifth-copy waits caused by an already concealed quad when establishing tenpai for declaration. Furiten blocks ron only. The snapshot supplies first-turn and furiten state. It lacks discard histories, opponent melds, wall contents, kan ownership, and other seats' responses. The four-kan cap suppresses further kans. Abortive draw settlement and competing calls are outside the action set.
- `called` represents chi or pon with its resulting concealed hand at 14−3k. The tile taken must occur in the specified meld, which must also occur in `melds`. Kuikae works by kind and bans the taken kind and, on the appropriate chi, the opposite sequence endpoint. The request is invalid if every resulting discard is forbidden.
- Chi tile pairs follow the canonical tile-list ordering. The draft's `chi:40m` example has the right ordering for 4m plus 0m, although `46m` and `40m` require different called tiles.
- `first=1` enables kyuushu even when other legal actions exist. Closed-hand tsumo already supplies a yaku on a complete shape.

## Corpus provenance and verification

`legal.txt` contains 1,323 original decision snapshots from six Akochan replay hands, 1,512 seeded suit permutations of replay decisions, and 165 directed snapshots. The seed is `0x4d4a`. The recorded moves check required actions for the replay and its suit permutations. The directed rows check required and forbidden actions for the edge cases listed in the brief. The generator uses the Rust evaluator for the full expected action sets, so the corpus self-check and recorded/hand-authored action checks provide different evidence.

Replay snapshots reconstruct permanent furiten from structural waits and the seat's own discards. They reconstruct temporary and riichi furiten from passed yaku-bearing wins. `generate_legal.py` reads the reference game only during corpus generation. Run `python3.14 -B corpus/rs/generate_legal.py` after building to reproduce the corpus.
