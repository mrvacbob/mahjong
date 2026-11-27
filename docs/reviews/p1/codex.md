# Phase 1 gate review — codex

**Verdict: hold the gate.** The checked-in Rust binary passes all 14,583 cases, including 3,000 legal and 5,198 score requests, with the documented harness. Several answers still encode rules that conflict with Mahjong Soul's ranked rules. The legal generator uses the same binary to produce the full expected action sets.

## Blockers

### 1. Riichi ankan may change the decomposition

**Files and cases:** `spec/formats.md` legal, `spec/rules.md` §1 and §5.3, `corpus/legal.txt` legal0073–0078, `agpl/mj-rs/src/state.rs` and `legal_fixtures.tsv`.

**Verdict:** The format's interpretation-preservation requirement is wrong for ranked play. The official ranked rules require identical wait kinds and forbid okurikan. They explicitly allow changes in shape and yaku. The FAQ also mentions wait counts. In this snapshot, comparing normalized wait kinds with a physically possible extra copy in the player's own hand plus melds suffices for these examples. Any external visibility semantics need a separate definition. [Ranked rules](https://mahjongsoul.com/news/46/) · [Mahjong Soul FAQ](https://mahjongsoul.com/faq/)

- **legal0073–0078:** Expect `ankan:<draw>,discard:<draw>` in all six cases. For legal0073, the only waits are 1m and 4m from 23m. With 999p fixed, the sou tiles split as either 333+456+66 or 33+345+666. Kanning the drawn 6s removes the first division and keeps the second as 33+345 plus declared 6666. Both waits still have the same number of possible copies. The remaining cases transpose suits and have the same derivation.
- **legal0061–0063:** Correct. The draw creates two copies, so only the drawn tile may be discarded.
- **legal0064–0066:** Correct. The kan consumes the drawn fourth copy and leaves the lone East tanki unchanged.
- **legal0067–0072:** Correct. In legal0067 the loose 4445s waits on 3s (345+44), 5s (444+55) and 6s (456+44). After ankan only 5s remains, so the draw must be discarded.

**Fix:** Change the legal contract and directed fixture, regenerate all six rows and audit the remaining corpus for this condition. The Rust adapter's `strict_ankan` rejects any pre-kan division without the fixed triplet. Upstream Mortal's `libriichi/src/state/update.rs` already calls `check_ankan_after_riichi(..., false)`. The discrepancy belongs to the snapshot adapter and the contract. Use a paired test with legal0067 and legal0073 to check that only the wait-changing kan is rejected. Replace or repair the §5.3 example, whose 9s tanki is straightforward but whose repeated sequences can also be described without invoking a specific yaku.

### 2. Dealer tenhou chooses the best winning tile

**Files and cases:** `spec/rules.md` §2.2, `spec/formats.md` Decision 12, `corpus/score.txt` sc910, sc918, sc3695, sc5136, `agpl/mj-rs/src/scoring.rs`.

**Verdict:** The ranked rules explicitly maximize the score over the choice of tsumo tile for tenhou. The current format and Rust evaluator use only the supplied winning tile. Treat `hand+win` as the complete opening hand and score every distinct winning-tile assignment, then apply the normal interpretation selection. Preserve the supplied draw for chiihou unless a source establishes a separate exception. [Ranked rules](https://mahjongsoul.com/news/46/)

| Case | Derivation | Correct answer |
|---|---|---|
| sc910 | 9m is duplicated. Treat it as the draw to leave all 13 unique orphans. | `yaku=kokushi_13:2,tenhou:1 yakuman=3 pay=all:48100 total=144300` |
| sc918 | 7m is the pair. Assign a 7m as the draw to leave all four triplets complete. | `yaku=suuankou_tanki:2,tenhou:1 yakuman=3 pay=all:48000 total=144000` |
| sc3695 | 7s is the pair. Assign a 7s as the draw, leaving the four triplets complete, and add one honba. | `yaku=suuankou_tanki:2,tenhou:1 yakuman=3 pay=all:48100 total=144300` |
| sc5136 | 7z is duplicated. Assign a 7z as the draw to leave all 13 unique orphans. | `yaku=kokushi_13:2,tenhou:1 yakuman=3 pay=all:48000 total=144000` |

Each currently pays 2×. I varied the nominated winning tile using the existing Rust binary for all 21 tenhou requests and found these four increases. Add a tenhou chuuren case where the supplied tile differs from the extra tile in the nine-sided base shape. Add the matching chiihou case to make the distinction explicit.

### 3. The legal event format cannot express ankan robbery

**Files and cases:** `spec/formats.md` legal, `spec/rules.md` §4.16, `corpus/legal.txt` legal0133–0138, `agpl/mj-rs/src/state.rs` and `generate_legal.py`.

**Verdict:** The same `discard=… flags=chankan` payload cannot distinguish a kakan, which can be robbed by any qualifying hand, from an ankan, which can be robbed only by kokushi. legal0133 permits ron for 23m on 1m with one open chi and no yaku other than chankan. That is correct for kakan. The identical winning shape must get only pass against ankan. The Rust adapter treats every chankan request as kakan. The replay generator emits response snapshots for kakan and skips them for ankan. Also, §4.16 mentions a 13-sided kokushi robbery, which would require five physical copies of the robbed kind across the two players. A single-wait kokushi can hold zero copies of the robbed kind. [Ranked rules](https://mahjongsoul.com/news/46/) · [Mahjong Soul FAQ](https://mahjongsoul.com/faq/)

**Fix:** Add an explicit robbery event or kan-type field, with ron/pass only. Test single-wait kokushi, a qualifying ordinary hand rejected against ankan, and furiten on a robbery opportunity. For example, `9m19p19s12345677z` can rob an ankan of 1m to make single-wait kokushi. If the benchmark keeps kakan only, narrow the contract explicitly.

## High severity

### 4. Ippatsu can survive a robbed added kan

**Files and cases:** `spec/rules.md` §4.15, §4.26 and §5.5, `spec/formats.md` Decision 10, `corpus/handwritten.txt` hw71–72.

**Verdict:** Allow the combination within the ippatsu window. A successful robbery resolves before the added kan completes. The official FAQ defines ippatsu through an uninterrupted turn and defines the robbery opportunity at the kan declaration. I infer the timing from those definitions and the uncompleted kan in §4.15. I did not verify the combination in a ranked client replay. A Mahjong Soul community explanation explicitly describes the combination. As independent evidence for the timing in another engine, Mortal's `state/update.rs` keeps `at_ippatsu` when `kakan` sets `chankan_chance` and clears it when a subsequent event consumes that opportunity. The adapted Rust score code already accepts both flags. [Mahjong Soul FAQ](https://mahjongsoul.com/faq/) · [Mahjong Soul community explanation](https://jantama.sinoa.ws/blog/?p=4921)

**Fix:** Specify that completed calls cancel ippatsu, and add hw71 with `flags=riichi,ippatsu,chankan`. The intervening opponent's pon of 5s can predate the riichi. The winner holds zero 5s. The win makes 567s on a two-sided wait and scores chankan, ippatsu, pinfu, riichi and tanyao for 5 han, 30 fu, `pay=ron:8000 total=8000`. A second companion case can exercise an earlier completed call by omitting ippatsu.

### 5. Pao honba is assigned to the liable seat, and Phase 1 cannot represent pao

**Files:** `spec/rules.md` §1 pao rows and §4.31–32, `spec/formats.md` score, `agpl/mj-rs/NOTES.md`.

**Verdict:** Daisangen/daisuushii liability, full payment on tsumo, half of the liable component on third-party ron, ordinary settlement of the other yakuman components, and no separate daiminkan or suukantsu liability agree with the ranked publication. The ranked text assigns honba to the liable player, conflicting with the table's claim that a third-party discarder pays honba. I did not verify the exact trigger when the final dragon or wind set is completed by daiminkan or when earlier sets are closed kans. The publication's separate statement about daiminkan liability does not spell out every interaction with dragon/wind pao. [Ranked rules](https://mahjongsoul.com/news/46/)

**Fix:** Correct the honba assignee and source the trigger examples before implementing settlement. State in the format that `score` returns the single-winner, pre-liability payment schedule. It has neither the seat that supplied each meld nor declaration order, and its payment output offers no split between the discarder and a liable third party. Actual pao settlement belongs in the later table engine.

### 6. Two scoring authorities disagree, and several examples invite wrong implementations

**Files:** `spec/rules.md` §3 and §4, `spec/formats.md` score and Decisions 3, 6, 7, `corpus/handwritten.txt` hw34, hw54, hw57–59, hw63, hw70.

- **Double-wind pair and rinshan fu:** Keep +4 and +2 respectively. The official text confirms both. In hw54 the pair and a closed terminal triplet produce 42 raw fu and therefore 50 fu. In hw70 the closed simple kan and tsumo produce 38 raw fu, therefore 40 fu. hw70 would still round to 40 without the 2 tsumo fu, so it does not discriminate the rule. Add a rounding-boundary case. For example, `hand=111m23p789s11z melds=k2222s win=4p by=tsumo seat=E round=E flags=rinshan` has 20+8+8+4+2=42 raw fu, rounded to 50, and pays 800 all at 1 han. Without tsumo fu it would round to 40 and pay 700 all. [Ranked rules](https://mahjongsoul.com/news/46/)
- **Kazoe, doubles and stacking:** Keep 13+ ordinary han as one yakuman with ordinary output fields. Keep kokushi_13, suuankou_tanki, junsei_chuuren and daisuushii at 2× and sum distinct natural yakuman. The official FAQ distinguishes the four variants, the ranked rules confirm stacking, and official release notes give the tenhou/big-four-winds/all-honors/four-concealed-triplets combination. The FAQ does not publish the numeric multipliers or kazoe cap in that list. hw58 (14 ordinary han) and hw63 (5× natural) exercise the proposed defaults. Decision 3 references a library-specific 6× cap that does not appear in the wire contract. If the cap is intended as a rule, establish its source and whether it ever binds a reachable Phase 1 hand. [Mahjong Soul FAQ](https://mahjongsoul.com/faq/) · [Ranked rules](https://mahjongsoul.com/news/46/) · [Official update on composite yakuman](https://mahjongsoul.com/news/40)
- **Interpretation ranking:** §3.1's phrase “highest han first” can be read as overriding payout ordering. A 3 han 70 fu ron earns 8000 while a 4 han 30 fu ron earns 7700. State the priority as total, then han, then fu. Decision 7 leaves natural-versus-kazoe ties outside the corpus. Choose natural yakuman on equal total, as the Rust adapter already does. Finish the rule with a deterministic tiebreak for equally ranked but differently named yaku lists, such as lexicographic order of the canonical list.
- **Examples:** §4.4's sample is capable of both standard and seven-pairs forms. Say that yaku from different divisions cannot combine and score the highest-paying division. §4.6 contains an abandoned example and shifts between tiles and waits in the same sentence. Replace it with hw58, where 8p can be a pair completion in one division or a ryanmen completion in another.

### 7. Legal corpus provenance leaves alternative actions unchecked

**Files:** `agpl/mj-rs/generate_legal.py`, `legal_fixtures.tsv`, `DISAGREEMENTS.md`, `NOTES.md`, `tools/harness.py`.

The replay checks establish that the recorded move was offered. They cannot establish that every alternative offered was legal. Even the directed cases assert subsets of required and forbidden actions. The rest of each answer is copied from the same adapter. For example, the legal0043 fixture requires chi:24m, while the adapter adds the independently valid chi:45m. A future extra action on that fixture can become an expected answer without a failed assertion. Also, the generator uses the Rust evaluator's candidate ron and waits to construct furiten, so one defect can affect both the input and the expected action. The furiten pass clears missed wins after a call or a non-riichi draw, while the official ranked text places the temporary-furiten reset at the next own draw. Inspect this when regenerating, especially a skipped ron followed by a chi/pon and another winning discard before the caller's next draw. I did not trace a specific affected replay row. [Ranked rules](https://mahjongsoul.com/news/46/)

Require complete hand-authored action sets for directed cases and have an independent evaluator or ranked replay verify the disputed interactions. Record provenance for the generated answer sets. Retain the Rust harness as a regression check. Its exact-string comparison is appropriate once canonical forms are defined. Update `DISAGREEMENTS.md` to label the older 140 differences as historical. Current answers for its examples sc741, sc742 and sc747 give the double-yakuman payouts, and the current binary passed all score answers. The reference ports game logic and adds custom scoring, decomposition and riichi checks. Agreement is evidence for tested outputs under shared assumptions, and the official rules remain the authority for those assumptions.

## Medium severity

### 8. Kuikae verdict and precise contract

**Files and cases:** `spec/rules.md` §1 and §4.12–13, `spec/formats.md` legal, `corpus/legal.txt` legal0025–0048, `agpl/mj-rs/src/chi_candidates.rs` and `state.rs`.

**Verdict:** The checked cases correctly implement the full swap ban. The official ranked text confirms swap-calling is disallowed. I did not find an official example enumerating the post-call action list or a ranked replay demonstrating a dead-end chi. The following exact logic matches the repo's stated rule and the hand derivations. [Ranked rules](https://mahjongsoul.com/news/46/)

- Pon forbids the called kind. Normal and red five share the restriction.
- Chi forbids the called kind and the other kind that could complete the same two consumed tiles into a sequence. That second ban exists only if the consumed tiles are adjacent and could make two sequences in the suit. Call 4 with 56 and forbid 4/7. Call 7 with 56 and forbid 7/4. Call 5 with 46 and forbid only the five kind. Call 3 with 12 and forbid only 3.
- A chi that consumes two tiles and leaves only forbidden kinds cannot be offered under this discard rule. legal0046 leaves 47 after taking 4 with 56. It still permits ron because 567 plus 44 completes the hand and the three wind pons include at least one value wind for the default East/ East context. The Rust chi candidates and post-call filters implement the same kind-based rule. A valid pon always leaves at least one permissible tile under four-copy counts and the hand size invariant.

**Fix:** Put the formula, red normalization and follow-up discard requirement in the legal contract. Define an impossible `called` snapshot as invalid input. Replace the misleading `chi:46m` / `chi:40m` example with `chi:40m` and `chi:45m` on the same 6m, as in legal0001.

### 9. Specify the domains where implementations can otherwise diverge

**Files:** `spec/formats.md` runner, tiles, shanten, waits, legal and Decisions 3–15, `corpus/disputed.txt`, `agpl/mj-rs/NOTES.md`.

- **Structural shanten versus legal tenpai.** Decision 4 deliberately accepts abstract fifth-copy tenpai for shanten. hw15 is structurally tenpai and hw25 correctly has no waits. Legal declaration should reject the fifth-copy-only shape, while allowing karaten caused by tiles elsewhere at the table. For hw25 plus a 9p draw, discarding 9p cannot lead to a legal riichi. The Rust `player_shanten` uses a different routine from `shanten` and excludes that action. Write the legal rule directly so reuse of the structural op produces the correct distinction. Explain that a complete 14-tile hand returns -1 before applying any discard analysis. [Ranked rules](https://mahjongsoul.com/news/46/)
- **Timing of wall and flags.** State that `wall` is counted after the incoming draw. Rust infers a last-tile yaku from `wall=0` even with no flag. A reader could use only flags and reach a different ron/tsumo answer. Define whether flags are required or derived, and ensure rinshan and robbery are excluded from live-wall inference. State that `kans` counts table-wide completed kans, including the caller's kans. Spell out the treatment of the final rinshan discard and of the fourth kan by multiple players, or bound the action set to snapshots where normal discard responses are still allowed. `kans=4` alone cannot encode kan ownership or a pending abort.
- **First-turn and riichi state.** `first=1` reads like an abortive-draw flag, while a full ranked first-turn draw can also supply a tsumo yaku for tenhou or chiihou. Rust uses `first` only for kyuushu, which still permits a valid closed-hand tsumo via menzen tsumo. Define the scope of `first`, keep already-declared riichi separate from scoring flags, and state `kakan` is unavailable after riichi. Specify the handling of internally contradictory snapshots as part of the input domain.
- **Input grammar and errors.** Say whether grouped tiles can repeat a suit or arrive unsorted, whether `melds` may be omitted, how to handle unknown/duplicate/extra keys, and whether input validation counts indicators toward the physical deck. For example, the fixture source accepts `40m5m123p789s1234z` and serializes it canonically as `405m123p789s1234z`. The runner asks for `error=<reason>` but Decision 15 leaves the labels beyond score's two errors to the implementations. Define one bad-input response for any malformed requests that are assessed, or confine correctness scoring to the stated valid domain.
- **Agari group comparator.** Decision 1 states that the comparator uses first digit before group type but gives `234m` versus `222m` as an example. They have the same first digit. Say explicitly that the group-type tie break applies to equal suit and first digit. Explicitly make known closed kans count as melds for shape operations and preserve menzen for scoring and legal. A declared ankan cannot be part of chiitoi or kokushi.

### 10. Coverage gaps and benchmark scope

**Files:** `corpus/*.txt`, `spec/formats.md`, `tools/harness.py`.

- **Legal:** Add the corrected waits-preserving ankan rows and a true okurikan negative case with a quad unrelated to the draw. Add a test combining furiten with a legal riichi declaration, paired with an otherwise similar hand that has only a fifth-copy wait. Add the ankan robbery discriminator and its yes/no pair. The six directed chankan rows cover only kakan; all 57 post-call snapshots are chi or pon. Add last-wall open win examples contrasting ordinary last-tile context and rinshan.
- **Score:** No score request combines chankan with ippatsu, and none supplies nonempty ura without riichi or double riichi. Add both, plus a rounding-sensitive rinshan test and a natural-versus-kazoe tie. The discarded Decision 7 example is suitable after the tie rule is ratified. Add tenhou's winning-tile reassignment with identical complete hands and different supplied winning tiles. Current examples include outright no-yaku and not-agari errors (the file scan counted 554 and 194 respectively in score.txt), so missing cases concern interactions.
- **Agari, shanten and waits:** Preserve dual standard/seven-pairs decomposition, the fifth-copy disagreement examples, and waits that account for tiles consumed by declared melds. The biggest missing common coverage is the malformed-input path required by the runner. None of the corpora expects a parse/validation error. If validation is evaluated, use a small shared set of exact bad-input answers and a following valid request to check recovery. Keep serialization minimal.
- **Slice:** Keep the five operations. Decomposition enumeration and memoization, placement-sensitive scoring, and composing the shape and yaku primitives into legal actions exercise different parts of each language. Keep game history, opponent call arbitration, liability and full match settlement outside the benchmark. The corpus's 3,000 legal rows contain 8,266 discard action entries but only 19 ron, 14 ankan and 9 daiminkan entries. Use the large corpus for throughput and a compact, independently audited set for semantic correctness. In particular, add an ambiguous scoring workload where candidate decompositions disagree on yaku and fu. This will exercise the algorithm and representation choices more directly than more permutations of passive replay snapshots.

## Hand-check record

I derived the action sets and the scores below from the request lines, then compared the selected expected answers. The 51 legal checks count individual rows, including suit permutations. The sample contains fewer distinct situations than rows.

| Legal IDs | Derivation of the complete action set |
|---|---|
| legal0025–0030 | Post-chi, remove the called 4 and alternate 7 in the chi suit from the discard list. Every other distinct physical tile can be discarded. |
| legal0031–0036 | Post-chi, forbid the called 7 and alternate 4. The concealed red 5 remains available, as do all other distinct tiles. |
| legal0037–0042 | Post-pon, the concealed red five has the called kind and is banned. All non-five tiles in the hand are available. |
| legal0043–0045 | On 3 with 2456, take 24 and discard 5 or 6, or take 45 and discard 2. In the latter call only 6 is banned among the residual 2 and 6. Three existing pons plus 23456 cannot form the needed set and pair for ron. Expect both chi actions and pass. |
| legal0046–0048 | On 4 with 4567, the only chi consumes 56 and leaves two forbidden kinds. Ron makes 44+567 with the three wind pons. Expect pass and ron. |
| legal0049, legal0055 | Draw completes closed 234m+456m+234p+678s+22z. Tsumo and every distinct discard are legal. Each discard can be restored to the winning shape by drawing its kind, so every discard can declare riichi at wall 4. At wall 3, none can. |
| legal0061–0078 | See the four independent riichi-ankan derivations in finding 1. The six waits-preserving rows are the discrepancies. |
| legal0079 | Every distinct tile in hand plus draw is discardable. 0m is the only tile that upgrades p555m, with no other kan, no complete concealed shape and an open hand. Expect those discards and kakan:0m. |
| legal0133–0138 | Added-kan robbery completes 123 in the receiving suit, with two other concealed sequences and a pair. Chankan provides the yaku, and chi/pon/kan are unavailable in a robbery response. Expect pass and ron. |

The 25 consecutive score cases below are from `corpus/handwritten.txt`. They match the expected lines. The four additional wrong score answers in `corpus/score.txt` are listed with derivations in finding 2. Tsumo amounts in this table use the protocol's nondealer/dealer order.

| Score ID | Hand derivation and payment |
|---|---|
| hw52 | 123m, 456p, 678s, 99s, concealed Chun. Chun 1 and three indicator dora. Closed ron plus honor triplet gives 38→40 fu, 8000 ron. |
| hw53 | East pon counts both winds. 4556p with the added 5 permits a closed-wait or pair completion, both worth 2 fu. 20+4+2→30 fu, 2 han, 2900 dealer ron. |
| hw54 | Closed terminal triplet plus double East pair, ryanmen. 20+10+8+4→50 fu, riichi only, 2400 dealer ron. |
| hw55 | Closed terminal kan and ryanmen, 20+10+32→70 fu. Riichi only, 2300 ron. |
| hw56 | Open Haku kan and 13m closed wait, 20+16+2→40 fu. Haku only, 1300 ron. |
| hw57 | 234m twice, 567p and 567s, 88s pair, ryanmen. Iipeikou, pinfu, riichi, tanyao and tsumo, 5 han 20 fu, 2000/4000. |
| hw58 | Pair 22p with doubled 345p and 678p gives ryanmen on 8p. Chinitsu 6, ryanpeikou 3, pinfu, riichi, tanyao and 2 dora. 14 han 30 fu, 32000 ron as kazoe. |
| hw59 | Same shape and placement without dora, 12 han 30 fu, 24000 ron. |
| hw60 | Three dragon triplets, 123m and 44m, daisangen 1×, 32000 ron. |
| hw61 | Same division with dealer tsumo. Three concealed triplets and a sequence still give only daisangen at yakuman level, 16000 all. |
| hw62 | All 13 distinct orphans before the ron, 2×, 64000 ron. |
| hw63 | Four concealed wind triplets and a white dragon tanki. Daisuushii 2×, suuankou tanki 2×, all honors 1×, 160000 ron. |
| hw64 | Ron completes Haku open. Three concealed triplets give sanankou, plus toitoi and Haku for 5 han. 20+10+8+4+4+4=50 fu, 8000 ron. |
| hw65 | Tsumo on the same shanpon completes the fourth concealed triplet, 1× suuankou, 8000/16000. |
| hw66 | Four sets and a pair, no natural yakuman, dealer opening win 1×, 16000 all. |
| hw67 | Same division, nondealer first uninterrupted draw 1×, 8000/16000. |
| hw68 | 234m, 567p, 345s and 678s, 88p, ryanmen. Haitei, pinfu, tanyao and tsumo, 4 han 20 fu, 1300/2600. |
| hw69 | Same shape, houtei instead of haitei and tsumo, 3 han 30 fu, 3900 ron. |
| hw70 | Closed simple kan and ryanmen, closed tsumo, tanyao and rinshan. 20+16+2→40 fu, 3 han, 1300/2600. |
| hw71 | Closed 234m, 567p, 234s and 567s, 88p, ryanmen. Chankan, pinfu and tanyao, 3 han 30 fu, 3900 ron. |
| hw72 | Same hand with double riichi and ippatsu in place of chankan, 5 han 30 fu, 8000 ron. |
| hw73 | Open ittsu in pin, East round pair and ryanmen, 1 han 30 fu, 1000 ron. |
| hw74 | Four terminal/honor triplets (the ron triplet counts as open) and a terminal pair. Honroutou and toitoi, 4 han 40 fu, 8000 ron. |
| hw75 | 234s twice, 666s, 666z and 88s are all green. Ryuuiisou 1×, 32000 ron. |
| hw76 | 111m, 999m, 111p, 999s, 99p are all terminals. Chinroutou 1×, 32000 ron. |

## Review limits

I ran the existing Rust binary through the full harness and inspected the adapters, fixtures and replay generation logic relevant to the findings. I did not rebuild Rust, regenerate any corpus, independently rerun the Python scoring oracle, or manually derive every generated case. I did not verify the exact ranked-client behavior of ippatsu during robbery, dead-end chi, or pao trigger variants in replays. I did not audit the match progression, abortive draw settlement, 3-player rules, or toolchain performance.

## Top findings

- Ranked riichi ankan permits changes in decomposition when the waits are preserved. Six legal fixtures reject it.
- Ranked tenhou maximizes over the winning-tile assignment. Four score fixtures underpay by one yakuman.
- The format needs separate kakan and ankan robbery semantics, and the rules should preserve ippatsu when an eligible ron interrupts an added kan.
- The 14,583-case Rust pass includes 3,000 legal answers produced by that same adapter. Independently verify complete action sets for the directed cases before using them as the comparison standard.
