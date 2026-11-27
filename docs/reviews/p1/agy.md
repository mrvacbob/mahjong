# Phase 1 Gate Review — `agy`

Reviewer: `agy`  
Scope: `spec/rules.md`, `spec/formats.md`, `corpus/legal.txt`, `corpus/score.txt`, `corpus/disputed.txt`, `tools/harness.py`, `tools/oracle_mj.py`, and `corpus/rs/src/{main,model,state,chi_candidates,scoring}.rs`.

---

## Findings Ordered by Severity

### Critical

#### 1. `legal` `riichi:<tile>` contradicts `formats.md` on 4-copy self-karaten tenpai
- **File / Case ID:** `spec/formats.md` (line 167, Decision 4 lines 197–205); `corpus/legal.txt` (`legal0157`, `legal0158`, `legal0159`); `corpus/rs/src/state.rs` (line 117) & `corpus/rs/src/model.rs` (lines 271–277).
- **What's wrong:** `spec/formats.md` Decision 4 defines `std` shanten as pure shanten ignoring tile availability, explicitly stating that a hand waiting only on a 5th copy (e.g. `234567789m1111z`) is tenpai (`std=0`). Line 167 then defines `riichi:<tile>` as `"discarding this tile leaves tenpai, wall>=4"`. However, in `legal0157` (`hand=111789m123p123s1z draw=1m kans=4`), discarding `1z` leaves `1111789m123p123s` (pure `std=0`, waiting only on a 5th `1m`), yet the expected output omits `riichi:1z` (same for `legal0158` omitting `riichi:1z`, `legal0159` omitting `riichi:1z`). This happens because `corpus/rs/src/model.rs` uses pure `shape::standard` for `shanten`/`waits`, but `state.rs` uses libriichi's Tenhou-penalized `player_shanten` (`shanten::calc_normal`, which returns `1`) for `legal`. Any implementer who reuses their spec-compliant `shanten` function for `legal` `riichi:` will fail `legal0157`–`legal0159`.
- **Proposed fix:** In Mahjong Soul and Tenhou, declaring riichi with a pure 5th-copy self-karaten wait is illegal (at least one wait tile must have a live copy outside your own hand/melds). Update `spec/formats.md` line 167 to state explicitly: `"discarding this tile leaves tenpai with at least one wait tile not already held in all four copies (i.e. waits count > 0)"`. Keep `legal0157`–`legal0159` as expected, and add a note in the Decisions log.

#### 2. `formats.md` omits that `flags=chankan` suppresses `chi`, `pon`, and `kan` in `legal`
- **File / Case ID:** `spec/formats.md` (lines 159–160, 173–175); `corpus/legal.txt` (`legal0133`–`legal0138`); `corpus/rs/src/state.rs` (line 168).
- **What's wrong:** `spec/formats.md` defines `chi`, `pon`, and `kan` in `legal` with conditions `"Not in riichi. wall>=1"` (plus `from=kamicha` for `chi`), and never states that `flags=chankan` suppresses calls. In `legal0133` (`hand=23m456p789s33z melds=c123s discard=1m from=kamicha flags=chankan`), `from=kamicha`, `wall=70`, `riichi=0`, and `23m` can form a sequence with `1m`, so a literal implementation of `formats.md` emits `chi:23m,pass,ron`, failing the expected `pass,ron` (same for `legal0134`–`legal0138`).
- **Proposed fix:** Add explicitly to `spec/formats.md` under `legal`: `"When flags=chankan is set, the tile is an opponent's added kan (not a discard), so only ron and pass are legal; chi, pon, and kan are forbidden."`

#### 3. Chankan + Ippatsu is wrongly forbidden in `spec/rules.md` and excluded from `corpus/score.txt`
- **File / Case ID:** `spec/rules.md` (item 26 line 272; Unverified item 5 line 293); `spec/formats.md` (Decision 10 lines 226–227); `corpus/score.txt`.
- **What's wrong:** `spec/rules.md` claims that declaring shouminkan cancels Ippatsu so Chankan cannot combine with Ippatsu, and `formats.md` Decision 10 excludes `ippatsu+chankan` from generated cases. Under **Mahjong Soul ranked rules** (as well as Tenhou, M-League, and standard riichi mahjong), **Chankan and Ippatsu DO stack** (`立直・一発・槍槓`). A call only cancels Ippatsu if the call *completes*; when robbed via Chankan, the kakan is interrupted and never completes (the same reason no kan dora flips, which `rules.md` item 15 already states).
- **Proposed fix:** Fix `spec/rules.md` item 26 to clarify that only *completed* calls cancel Ippatsu and that Chankan on a shouminkan combines with Ippatsu; remove Unverified item 5. Remove `ippatsu+chankan` from `formats.md` Decision 10's impossible combinations, and add `score` corpus cases with `flags=riichi,ippatsu,chankan` and `flags=double_riichi,ippatsu,chankan`. (Both `tools/oracle_mj.py` and `corpus/rs/src/scoring.rs` already score this combination.)

#### 4. Riichi `ankan` rule in `formats.md` and `legal0073`–`legal0078` does not match Mahjong Soul (and is underspecified)
- **File / Case ID:** `spec/formats.md` (line 169); `spec/rules.md` (line 69, item 14 line 260, Unverified item 3 line 291); `corpus/legal.txt` (`legal0073`–`legal0078`); `corpus/rs/src/state.rs` (lines 244–281).
- **What's wrong:** Two compounding issues:
  1. **Ruleset mismatch:** `formats.md` line 169 requires that a riichi ankan `"changes neither waits nor hand interpretation"`, and `legal0073`–`legal0078` (e.g. `legal0073`: `hand=23m999p33345666s draw=6s riichi=1` -> `actions=discard:6s`) forbid `ankan:6s` even though waits remain `{1m, 4m}` before and after (`33345666s` has decompositions `333+456+66` and `33+345+666`; after `ankan:6s`, `33345s` = `33+345` still waits `{1m, 4m}`). Both **Mahjong Soul** and **Tenhou** explicitly allow riichi ankan whenever the wait tile set does not change, even if mentsu structure/hand interpretation changes (`「リーチ後、待ち牌の種類と枚数が変わる暗槓、および送り槓は不可とします。上記以外の牌姿が変わる暗槓は可とします。」`). The `"neither waits nor hand interpretation"` rule is M-League/JPML/WRC, not Mahjong Soul.
  2. **Ambiguity:** Even if the stricter rule were intended, `"changes neither waits nor hand interpretation"` is too vague for independent implementers. `state.rs`'s `strict_ankan` checks that for every live wait tile, every pre-ankan winning form contains `(kan, triplet)` and removing that triplet produces the exact set of post-ankan forms (and also returns `false` if a riichi hand is karaten on all waits). Another implementer might reasonably check only whether the highest-scoring yaku/fu changes, or whether wait type (ryanmen/tanki/shanpon) changes.
- **Proposed fix:** Align `formats.md`, `rules.md`, `state.rs`, and `legal0073`–`legal0078` with Mahjong Soul's actual rule: riichi ankan is legal iff it is the drawn tile and the set of wait tiles (specify whether pure waits or live waits; Mahjong Soul/Tenhou check wait tile kinds) is identical before and after removing the quad. (If the project instead deliberately wants the strict M-League rule, document the exact `agari`-form projection definition in `formats.md` and record the intentional deviation from Mahjong Soul in `rules.md`.)

---

### High

#### 5. `legal` `wall=0` implicitly granting `haitei`/`houtei` is unspecified in `formats.md`
- **File / Case ID:** `spec/formats.md` (lines 155, 159–160, 168, 172); `corpus/rs/src/state.rs` (lines 94, 163).
- **What's wrong:** `state.rs` grants a situational yaku whenever `self.wall == 0`, even if `flags=haitei` or `flags=houtei` is omitted. `formats.md` says `"In the draw case, flags may carry rinshan or haitei; in the discard case, houtei or chankan"` without stating whether `wall=0` alone implies `haitei`/`houtei`. Also note that a `rinshan` draw after a kan at `wall=1` leaves `wall=0` and is *not* `haitei` (it is `rinshan`).
- **Proposed fix:** State explicitly in `formats.md` that situational yaku in `legal` come from `flags=` (and never silently from `wall=0`), and ensure every corpus case representing a haitei draw or houtei discard passes `flags=haitei`/`flags=houtei` alongside `wall=0`.

#### 6. Missing `legal` test coverage for critical rules inside the 5 ops
- **File / Case ID:** `corpus/legal.txt`.
- **What's wrong:** Several important rules in `legal` have zero directed coverage:
  - **Riichi okurikan**: No case where a riichi player already holds 4 copies of tile `X` and draws a different tile `Y`, verifying `ankan:X` is forbidden.
  - **Non-riichi `ankan`**: No directed case for legal non-riichi `ankan:<kind>` (drawn or already in hand) or `ankan` blocked by `wall=0`.
  - **Closed hand with `ankan` can still `riichi` and `tsumo`**: No directed case with `melds=a...` verifying `riichi:<tile>` and menzen `tsumo` remain legal (whereas `c`/`p`/`k`/`s` block `riichi`).
  - **Kuikae after `kanchan` and `penchan` chi**: Only ryanmen chi (`c406m took=4m`, `c567m took=7m`) and pon (`p555m`) are tested; no kanchan (`c406m took=0m`, forbidding only `5m/0m`) or penchan (`c123m took=3m`, `c789m took=7m`) cases exist.
  - **`kakan` blocked by `wall=0`** and **`kakan:5m` on `p055m`**.
  - **`kyuushu` 8-vs-9 boundary**: `legal0085`–`0087` have 12 distinct terminal/honor kinds; no case tests 8 distinct kinds (especially 9+ tiles of only 8 distinct kinds due to pairs) returning no `kyuushu`.
  - **`riichi=1` satisfying yaku requirement for `ron`**: No directed case tests a yaku-less closed hand winning by `ron` solely because `riichi=1` (with `furiten=0` vs `furiten=1`).
- **Proposed fix:** Add ~20–30 targeted directed fixtures to `corpus/legal.txt` covering each of the above.

---

### Medium

#### 7. `score` tie-breaking between real yakuman and kazoe yakuman is only in the Decisions log
- **File / Case ID:** `spec/formats.md` (lines 120–121, Decision 7 lines 211–216).
- **What's wrong:** The main `score` specification says `"The interpretation with the highest total wins; ties go to higher han, then higher fu."` When a real yakuman (e.g. `suuankou`) ties a kazoe yakuman (e.g. 13+ han `chinitsu`) on `total`, `"higher han"` is undefined for yakuman. Decision 7 notes this and suggests updating the spec, but the main section was not updated.
- **Proposed fix:** Add to `spec/formats.md` line 121: `"A natural yakuman beats a kazoe yakuman of the same total."`

#### 8. `formats.md` `legal` section does not define kuikae or cross-reference `spec/rules.md`
- **File / Case ID:** `spec/formats.md` (lines 166, 173).
- **What's wrong:** `formats.md` mentions `"Kuikae-forbidden tiles"` in `legal` without defining kuikae or pointing to `spec/rules.md` (unlike `score`, which explicitly points to `spec/rules.md` at line 142). It also does not specify whether `took=<tile>` matches by kind (treating red `0` and plain `5` as equivalent).
- **Proposed fix:** Explicitly reference `spec/rules.md` in the `legal` section and summarize the exact kuikae rule (same kind as `took`, plus opposite-end suji tile for ryanmen chi, treating `0` and `5` as the same kind).

#### 9. `spec/rules.md` item 6 contains garbled draft prose and invalid tile examples
- **File / Case ID:** `spec/rules.md` (line 252, Section 4 item 6).
- **What's wrong:** Item 6 contains unedited thinking-out-loud text (`"Closed 1234m 456p 789s 234s 99p? ... (234 + 4-4? no, ...)"`) and broken mahjong examples: `23456m` does not wait on `2m/5m` (`23456m + 2m = 223456m` is not complete; `2345m` is nobetan), and `23444m` does not wait on `2m` (`223444m` is not complete).
- **Proposed fix:** Replace item 6 with a clean, valid example, e.g. `2345m 234p 567p 678s 88s`? (Wait: `2345m` is 4 tiles -> `2345m 234p 567p 678s` is 13 tiles, nobetan waiting `2m/5m`, tanki only; for a genuine pinfu-vs-fu ambiguity, use `234566778m 234p 88s` or `345678m 234p 456s 7s` -> e.g., `23444m 234p 567p 88s` waiting on `5m`? Still no; use `2233445m 234p 678s` winning on `5m`: `234m+234m+55m` (tanki, iipeikou, no pinfu) vs `22m+345m+345m` (ryanmen `5m` on `34m`, pinfu + iipeikou)!).

#### 10. `legal` cannot represent `chankan` on `ankan` (Kokushi-only)
- **File / Case ID:** `spec/formats.md` (lines 160, 172); `spec/rules.md` (line 78, item 16 line 262).
- **What's wrong:** `legal` has only a single `flags=chankan` flag and treats any complete hand as able to `ron` on it. It cannot distinguish robbing a shouminkan (any hand) from robbing an ankan (Kokushi Musou only).
- **Proposed fix:** Explicitly document in `formats.md` that `flags=chankan` in `legal` means robbing a **shouminkan** (and robbing an ankan for Kokushi is out of scope for Phase 1/2 `legal`, or add `chankan_ankan`).

---

### Low

#### 11. `formats.md` does not state dora indicator wrapping or red-five indicator behavior
- **File / Case ID:** `spec/formats.md` (lines 66–67, 119); `corpus/score.txt` (e.g. `sc186`, `sc3080`, `sc3134`, `sc4166`).
- **What's wrong:** Several `score.txt` cases pass a red five as a dora indicator (e.g. `dora=0m` in `sc3134`). `formats.md` never explicitly states the indicator-to-dora successor mapping (`1..8->n+1`, `9->1`, `0->6`, `1z..3z->n+1`, `4z->1z`, `5z..6z->n+1`, `7z->5z`) or that `0` as an indicator gives the same dora (`6`) as `5` with no extra aka bonus.
- **Proposed fix:** Add a one-sentence specification of dora indicator wrapping (including `0 -> 6`) in `formats.md`.

#### 12. `formats.md` does not explicitly state red-five distinctness for `riichi:<tile>` and `kakan:<tile>`
- **File / Case ID:** `spec/formats.md` (lines 166–167, 170).
- **What's wrong:** Line 166 states `(red and non-red five are distinct)` for `discard:<tile>`, but lines 167 (`riichi:<tile>`) and 170 (`kakan:<tile>`) do not repeat this (though line 43 states generally that red fives are distinct in `legal` actions).
- **Proposed fix:** Clarify in lines 167 and 170 that `0` and `5` are distinct (e.g. both `riichi:0m` and `riichi:5m` if both are held and discarding a 5m leaves tenpai; `kakan:0m` vs `kakan:5m`).

#### 13. `rules.md` omits Mahjong Soul's 6x yakuman cap (mentioned in `formats.md` Decision 3)
- **File / Case ID:** `spec/rules.md` (line 56, 193); `spec/formats.md` (Decision 3 line 194); `corpus/rs/src/scoring.rs` (line 87).
- **What's wrong:** `formats.md` Decision 3 mentions `"6x yakuman cap"`, while `rules.md` states unbounded `8000 * N` and `scoring.rs` has no cap. Under Mahjong Soul ranked rules (without local yakuman), 6x is the theoretical maximum (`daisuushii:2 + suuankou_tanki:2 + tsuuiisou:1 + tenhou/chiihou/suukantsu:1`), so this has no practical effect on valid hands, but the docs should be consistent.
- **Proposed fix:** Note in `spec/rules.md` line 56 that Mahjong Soul caps stacked yakuman at 6x (which is also the theoretical maximum without local yakuman).

#### 14. `formats.md` Runner contract vs Decision 15 on error codes
- **File / Case ID:** `spec/formats.md` (line 22, Decision 15 lines 241–242).
- **What's wrong:** Line 22 requires `<id> error=<reason>` for unhandled requests without clarifying whether error `<reason>` strings beyond `not_agari` and `no_yaku` are tested. Decision 15 clarifies that no corpus case expects other error strings.
- **Proposed fix:** Move that clarification into the Runner contract ("Only `error=not_agari` and `error=no_yaku` are tested by the corpus; any other `<reason>` string is free-form").

---

## Specific Brief Questions (1–8)

### 1. Can chankan combine with ippatsu?
- **Verdict:** **Yes — `spec/rules.md` (item 26) and `spec/formats.md` (Decision 10) are WRONG.**
- **Evidence:** Under Mahjong Soul ranked rules (and Tenhou, M-League, WRC), robbing a shouminkan via Chankan interrupts the kan before it completes. Because the kan does not complete, Ippatsu is **not** cancelled, and `riichi + ippatsu + chankan` (+3 han) is a valid, well-known combination (e.g., punishing an opponent's attempted ippatsu-keshi kakan). `rules.md` item 15 already correctly notes that no kan dora flips because the kan is robbed; the same timing preserves Ippatsu.

### 2. Riichi ankan: is "neither waits nor hand interpretation change" Mahjong Soul's rule?
- **Verdict:** **No — Mahjong Soul (and Tenhou) use the permissive waits-only rule.**
- **Evidence:** Mahjong Soul's ranked rules state that after riichi, okurikan and any ankan that changes the wait tiles are forbidden, while ankan that changes hand composition/mentsu structure (`牌姿が変わる暗槓`) while preserving waits is **allowed** (matching Tenhou's official manual: `リーチ後の暗槓は待ち牌が変わらない場合のみ。送り槓不可、牌姿や役の増減は不問。`).
- **`legal.txt` cases exercising riichi ankan:**
  - `legal0064`–`legal0066` (`111789m123p123s1z draw=1m riichi=1` -> `ankan:1m,discard:1m`): Isolated triplet, waits (`1z`) and structure unchanged. **Correct under both rules.**
  - `legal0067`–`legal0072` (`123456m4445s111z draw=4s riichi=1` -> `discard:4s`): Waits `{3s, 5s, 6s}` would shrink to `{5s}`. **Correct under both rules.**
  - `legal0073`–`legal0078` (`23m999p33345666s draw=6s riichi=1` -> `discard:6s`): Waits are `{1m, 4m}` both before (`333+456+66` or `33+345+666`) and after (`33+345 + a6666s`), but the `333+456+66` decomposition disappears. **Wrong for Mahjong Soul** (should include `ankan:6s`); matches `formats.md`'s stricter M-League/JPML wording.

### 3. Kuikae: exact forbidden discards, `legal.txt` match, and dead-end chi omission
- **Verdict:** **Rule, `legal.txt` cases, and dead-end chi omission are all CORRECT.**
- **Exact rule (Mahjong Soul & Tenhou):**
  - After **Pon** of `X`: cannot discard `X` (same tile kind, red `0` == plain `5`).
  - After **Chi** of `X` with `Y, Z`: cannot discard `X` (same kind, `0` == `5`). Additionally, if `X` is the **low** end of a ryanmen sequence (`X, X+1, X+2` with `X <= 6`), cannot discard `X+3`; if `X` is the **high** end (`X-2, X-1, X` with `X >= 4`), cannot discard `X-3`. For kanchan (`X-1, X, X+1`) or penchan (`12[3]`, `[7]89`), only `X` is forbidden.
- **`legal.txt` cases:** `legal0025`–`0030` (`c406m took=4m` forbids `4m, 7m`), `legal0031`–`0036` (`c567m took=7m` forbids `4m, 7m`, allows `0m`), `legal0037`–`0042` (`p555m took=5m` forbids `0m`), `legal0043`–`0045` (`2456m` chi `3m`: `chi:24m` leaves `56m`, `chi:45m` leaves `26m` with `2m` legal), `legal0046`–`0048` (`4567m` chi `4m`: `chi:56m` leaves `47m`, both forbidden -> `chi:56m` omitted). All match.
- **Dead-end chi omission:** Correct. In Mahjong Soul and Tenhou, a chi that leaves no legal non-kuikae discard is illegal and not offered. (Pon can never be dead-end because at most 1 copy of the ponned kind can remain in the >=2 remaining concealed tiles.)

### 4. Fu and scoring rulings in `spec/rules.md`
- **Double-wind pair = 4 fu:** **Correct** for Mahjong Soul ranked (and Tenhou).
- **Rinshan tsumo fu = +2 fu:** **Correct** for Mahjong Soul ranked (and Tenhou).
- **Kazoe yakuman (>=13 han, capped at 1x):** **Correct** for Mahjong Soul ranked (and Tenhou).
- **Four double yakuman (`suuankou_tanki`, `kokushi_13`, `junsei_chuuren`, `daisuushii`):** **Correct** for Mahjong Soul ranked.
- **Yakuman stacking:** **Correct** (multipliers sum; note Mahjong Soul's 6x cap is omitted in `rules.md`, though 6x is the theoretical max without local yakuman).
- **Pao:** **Correct** for Mahjong Soul ranked (`pao_daisangen=true`, `pao_daisuushii=true`, `pao_suukantsu=false`; tsumo 100% + honba; ron 50/50 with discarder paying honba; composite yakuman applies pao only to the liable yakuman, with Daisuushii's full 2x covered by pao).

### 5. Hand-checked cases (26 `legal` + 26 `score`)

#### `legal` (26 cases checked; 2 disagreements found: `legal0073`, `legal0157` — plus `legal0133` spec gap)

| Case | Derived Result | Expected | Status |
| :--- | :--- | :--- | :--- |
| `legal0001` | `chi:40m,chi:45m,pass` (red/plain 5m distinct) | `chi:40m,chi:45m,pass` | Match |
| `legal0013` | `pass` (`from=shimocha`, no chi) | `pass` | Match |
| `legal0019` | `kan:5m,pass,pon:05m,pon:55m` (3 copies of 5m incl. 0m) | `kan:5m,pass,pon:05m,pon:55m` | Match |
| `legal0025` | All hand tiles except `4m,7m` (kuikae on `c406m took=4m`) | `discard:1p,1z,2p,3p,6m,7s,8s,9s` | Match |
| `legal0031` | All hand tiles except `4m` (kuikae `4m,7m` on `c567m took=7m`; `0m` ok) | `discard:0m,1p,1z,2p,2z,3p,3z,7s,8s,9s` | Match |
| `legal0037` | All hand tiles except `0m` (kuikae `5m/0m` on `p555m took=5m`) | `discard:1p,1z,2p,2z,3p,3z,4z,7s,8s,9s` | Match |
| `legal0043` | `chi:24m,chi:45m,pass` (`chi:45m` leaves `26m`, `2m` legal) | `chi:24m,chi:45m,pass` | Match |
| `legal0046` | `pass,ron` (`p111z` is E yakuhai; `chi:56m` leaves `47m`, all kuikae) | `pass,ron` | Match |
| `legal0049` | 12 `discard:*`, 12 `riichi:*`, `tsumo` (complete hand, `wall=4`) | Same | Match |
| `legal0055` | 12 `discard:*`, `tsumo` (`wall=3` blocks riichi) | Same | Match |
| `legal0064` | `ankan:1m,discard:1m` (riichi, isolated `111m`, wait `1z` unchanged) | `ankan:1m,discard:1m` | Match |
| `legal0067` | `discard:4s` (riichi, `ankan:4s` shrinks waits `{3s,5s,6s}` to `{5s}`) | `discard:4s` | Match |
| **`legal0073`** | **`ankan:6s,discard:6s` under Mahjong Soul** (waits `{1m,4m}` unchanged; `33345666s` -> `33345s + a6666s`) | `discard:6s` | **Wrong under Majsoul** (same for `0074`–`0078`) |
| `legal0079` | 10 `discard:*`, `kakan:0m` (`p555m` + `0m` in hand) | Same | Match |
| `legal0085` | 14 `discard:*`, `kyuushu` (`first=1`, 12 distinct terminal/honor kinds) | Same | Match |
| `legal0091` | `pass` (`furiten=1` blocks ron) | `pass` | Match |
| `legal0097` | 12 `discard:*`, 12 `riichi:*`, `tsumo` (`furiten=1` allows tsumo/riichi) | Same | Match |
| `legal0103` | `pass` (open hand, dora only, no yaku) | `pass` | Match |
| `legal0115` | 10 `discard:*`, `tsumo` (`flags=haitei` provides yaku) | Same | Match |
| `legal0127` | 10 `discard:*`, `tsumo` (`flags=rinshan` provides yaku; `k1111z` not yakuhai for S/S) | Same | Match |
| `legal0133` | `pass,ron` (`flags=chankan` provides yaku and suppresses `chi:23m`) | `pass,ron` | Match (spec omits suppression!) |
| `legal0139` | `pass` (`wall=0` blocks pon/kan/chi) | `pass` | Match |
| `legal0151` | `pass,pon:05m,pon:55m` (`kans=4` blocks `kan:5m`, allows pon) | `pass,pon:05m,pon:55m` | Match |
| **`legal0157`** | 11 `discard:*`, `riichi:1m` — **plus `riichi:1z` if using `formats.md`'s pure shanten!** (`1111789m123p123s` is pure `std=0` per Decision 4, but 0 live waits) | 11 `discard:*`, `riichi:1m` | **Contradicts `formats.md`** (same for `0158`–`0159`) |
| `legal1506` | `discard:1p,2m,3p,4p,5s` (`c456m took=6m` forbids `3m,6m`) | Same | Match |
| `legal2833` | 10 `discard:*`, `riichi:4p,riichi:5p,riichi:8p` (`11m+234m+345m` + `455678p` -> discarding `4p/5p/8p` leaves tenpai) | Same | Match |

#### `score` (26 cases checked; 0 errors found)

| Case | Derivation | Expected | Status |
| :--- | :--- | :--- | :--- |
| `sc1` | `chiitoi:2, riichi:1` (3 han 25 fu), non-dealer ron `3200 + 5*300 = 4700` | `chiitoi:2,riichi:1 han=3 fu=25 ron:4700` | Match |
| `sc11` | `ittsu:2, riichi:1, tsumo:1` (4 han); `55z` pair breaks pinfu -> `20+2+2=24->30 fu`; dealer 4/30 (no kiriage) `3900 all` (`11700`) | `ittsu:2,riichi:1,tsumo:1 han=4 fu=30 all:3900` | Match |
| `sc15` | `ryanpeikou:3, riichi:1, tsumo:1, aka:1` (6 han); kanchan `5s` -> `20+2+2=24->30 fu`; haneman +1 honba `3100/6100` (`12300`) | `aka:1,riichi:1,ryanpeikou:3,tsumo:1 han=6 fu=30 tsumo:3100/6100` | Match |
| `sc23` | `double_riichi:2, sanankou:2, tsumo:1, yakuhai_chun:1, yakuhai_seat:1, dora:3` (10 han); `20+2+4+8+8=42->50 fu`; baiman `4000/8000` | Same | Match |
| `sc48` | `pinfu:1, riichi:1, ippatsu:1, ura:1` (4 han 30 fu); non-dealer ron 4/30 (no kiriage) `7700` | Same | Match |
| `sc50` | `chinitsu:6, ittsu:2, iipeikou:1, riichi:1, ippatsu:1, tsumo:1, ura:1` (13 han kazoe); `20+2+2=24->30 fu`; `8000/16000` | Same | Match |
| `sc193` | `toitoi:2, yakuhai_hatsu:1, rinshan:1, aka:1, dora:3` (8 han); `20+2(rinshan)+4+8+16+4+2(tanki)=56->60 fu`; dealer baiman +2 honba `8200 all` | Same | Match |
| `sc200` | `honitsu:2, toitoi:2, yakuhai_chun:1, dora:3` (8 han); `20+16+2+4+4+2(tanki)+4(double-wind 11z)=52->60 fu`; dealer baiman +1 honba `24300` | Same | Match |
| `sc1230` | `riichi:1, yakuhai_haku:1` (2 han); `20+10+8+4(double-wind 44z)=42->50 fu`; non-dealer ron 2/50 `3200+300=3500` | Same | Match |
| `sc3104` | `riichi:1, rinshan:1, sanankou:2, sankantsu:2, tsumo:1, yakuhai_chun:1, dora:4, ura:1` (13 han kazoe); `20+2+32*3=118->120 fu`; dealer `16000 all` | Same | Match |
| `sc3243` | `chinitsu:6, double_riichi:2, ippatsu:1, tsumo:1, dora:4, ura:4` (18 han, capped 1x kazoe); `20+2+4+4+2=32->40 fu`; +1 honba `8100/16100` | Same | Match |
| `sc4867` | `daisuushii:2, tsuuiisou:1` (`yakuman=3`); dealer ron `3*48000 + 4*300 = 145200` | Same | Match |
| `sc4872` | `suuankou_tanki:2` on ron (`yakuman=2`); non-dealer ron `64000` | Same | Match |
| `sc4932` | `kokushi_13:2` (`yakuman=2`); non-dealer tsumo `16000/32000` | Same | Match |
| `sc4966` | `ryuuiisou:1` (`yakuman=1`); dealer ron `48000` | Same | Match |
| `sc4990` | `daisangen:1, suuankou_tanki:2, suukantsu:1, tsuuiisou:1` (`yakuman=5`); dealer tsumo `80000 all` (`240000`) | Same | Match |
| `sc5000` | `chinitsu:6, pinfu:1, ryanpeikou:3, tanyao:1, tsumo:1` (12 han 20 fu, no Daisharin); dealer sanbaiman `12000 all` | Same | Match |
| `sc5002` | 7-pair all honors -> `tsuuiisou:1` (no Daichisei); dealer ron `48000` | Same | Match |
| `sc5008` | Open pinfu-shape tsumo: `tanyao:1`, `20+2=22->30 fu`; `300/500` (`1100`) | Same | Match |
| `sc5010` | Incomplete hand (`344s`) -> `error=not_agari` | `error=not_agari` | Match |
| `sc5012` | Kanchan wait + `22z` pair, dora/aka only -> `error=no_yaku` | `error=no_yaku` | Match |
| `sc5104` | `chinitsu:6, toitoi:2, sanankou:2, tanyao:1, riichi:1, dora:16` (28 han, capped 1x kazoe); `20+10+4+4+2(open 777m)+16=56->60 fu`; ron `32000` | Same | Match |
| `sc5105` | Open pinfu-shape ron: `tanyao:1`, fixed `30 fu`; ron `1000` | Same | Match |
| `sc5125` | Shanpon ron on 3 concealed triplets -> `sanankou:2, toitoi:2` (not suuankou); `20+10+4+2+8+4=48->50 fu`; ron `8000` | Same | Match |
| `sc5132` | Ankan `a9999p` breaks Chuuren -> `chinitsu:6`; `11p+123p+456p+678p`, penchan `3p`, `20+10+32+2=64->70 fu`; ron `12000` | Same | Match |
| `sc5133` | `daisuushii:2, suuankou_tanki:2, tenhou:1, tsuuiisou:1` (`yakuman=6`); dealer tsumo `96000 all` (`288000`) | Same | Match |

*(Note: `sc5139` / `sc5140` also combine `tenhou`/`chiihou` with `kokushi_13:2`, which matches Decision 12.)*

### 6. Ambiguities in `spec/formats.md`
Summarized from Findings 1, 2, 4, 5, 7, 8, 10, 11, 12, 14 above:
1. `legal` `riichi:<tile>` tenpai check (pure `shanten == 0` vs `waits.count > 0`) — causes immediate failure on `legal0157`–`0159`.
2. `legal` `flags=chankan` suppressing `chi`/`pon`/`kan` — causes immediate failure on `legal0133`–`0138`.
3. `legal` riichi `ankan` `"changes neither waits nor hand interpretation"` — underspecified predicate (and wrong for Mahjong Soul).
4. `legal` `wall=0` vs explicit `flags=haitei`/`houtei`.
5. `score` tie-break between real yakuman and kazoe yakuman (in Decision 7, missing from main spec).
6. `legal` kuikae definition and red-five equivalence on `took=<tile>` (not defined or cross-referenced in `legal`).
7. `score` dora indicator wrapping (especially red `0` as an indicator -> `6`).
8. `legal` red-five distinctness on `riichi:<tile>` and `kakan:<tile>`.

### 7. Coverage gaps inside the five ops
1. `score`: `ippatsu + chankan` (and `double_riichi + ippatsu + chankan`).
2. `legal`: Riichi `okurikan` (already holding 4 copies, drawing another tile).
3. `legal`: Non-riichi `ankan` (legal, and blocked by `wall=0`).
4. `legal`: Closed hand with `ankan` (`melds=a...`) still allowed `riichi` and menzen `tsumo`.
5. `legal`: Kuikae after `kanchan` chi and `penchan` chi.
6. `legal`: `kakan` blocked by `wall=0`, and `kakan:5m` on `p055m`.
7. `legal`: `kyuushu` 8-vs-9 distinct-kinds boundary (e.g. 10 terminal/honor tiles of only 8 distinct kinds).
8. `legal`: `riichi=1` providing the sole yaku for `ron` (`furiten=0` vs `furiten=1`).

### 8. Is the slice the right size and shape for comparing languages?
- **Overall shape:** Good size for a 4-language shootout (`agari`/`shanten`/`waits` test backtracking, memoization, and data-structure ergonomics; `score` tests ADTs/pattern matching and rule composition).
- **What is mostly bookkeeping/noise:**
  - `corpus/legal.txt` has ~2,835 replay-derived cases that are overwhelmingly trivial `actions=pass` or plain `discard:` listings, testing parsing/string-formatting throughput rather than interesting logic. Trimming the replay tail (while adding the missing directed edge cases in Question 7) would tighten signal-to-noise.
  - `agari`'s custom group sort order (suit -> first digit -> pair < sequence < triplet -> string-sorted forms) is pure presentation bookkeeping, though small enough to keep as a decomposition-completeness check.
- **What is missing that would better separate Swift, Mercury, Python, and Haskell:**
  - A **14-tile discard-efficiency (`ukeire`)** op (or a heavier `shanten`/`waits` stress subset of chinitsu/1-shanten/2-shanten hands): given a 14-tile hand, return the discards minimizing resulting `shanten` and maximizing `waits.count`. It requires almost zero new rules or parsing, reuses `shanten`/`waits`, and sharply separates Mercury's nondeterminism/tabling, Haskell's laziness/arrays, Swift's value-type speed, and Python's interpreter overhead.

---

## What Was Not Checked

- **Did not execute `tools/harness.py` or `corpus/rs/target/release/mj-rs`**: Shell execution in this environment failed with a sandbox configuration error (`readonly /Users/astrange/Projects/emu/smcdis/*: globs not supported`). All code and corpus checks were done by static inspection and hand derivation.
- **Did not exhaustively inspect all corpus cases**: Checked 26 `legal` cases (out of 3,000) and 26 `score` cases (out of 5,143), plus the full implementations of `corpus/rs/src/{main,model,state,chi_candidates,scoring}.rs` and `tools/oracle_mj.py`.
- **Did not hand-check `corpus/agari.txt`, `corpus/shanten.txt`, or `corpus/waits.txt`** beyond their first 100 lines and `corpus/disputed.txt`.
- **Did not inspect `tools/gen/generate.py`, `tools/mjfmt.py`, `corpus/rs/src/algo/*`, or `3p/`**.
- **Did not verify in-client Mahjong Soul replays** for the non-slice game-flow rules in `spec/rules.md` Section 5 (multi-ron honba `上家取り` vs all-winners, post-kan ron kan-dora timing, Nagashi Mangan + All-Last tenpai-yame, or whether Mahjong Soul upgrades `tenhou` into `kokushi_13`/`suuankou_tanki`/`junsei_chuuren`).
