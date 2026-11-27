# Design: Python 3.14 Riichi Mahjong Engine (`shootout/python/agy`)

## Overview

The engine is implemented as a type-annotated Python 3.14 package (`mjlib/`) using only the standard library, invoked by a thin executable wrapper `./mj`. It is structured into six focused modules:

- `mjlib/tiles.py` — Tile/meld representation, canonical mpsz parsing and formatting, dora mapping.
- `mjlib/decompose.py` — Standard 4-meld+pair, chiitoitsu, and kokushi decomposition, plus `agari` formatting.
- `mjlib/shanten.py` — Structural shanten (`std`, `chiitoi`, `kokushi`, `min`) and `waits`.
- `mjlib/yaku.py` — Declarative yaku/yakuman rules, fu calculation, payment arithmetic, interpretation selection (`score`).
- `mjlib/legal.py` — Turn/response legality (`draw`, `discard`, `called`) reusing shanten, waits, and scoring.
- `mjlib/cli.py` — Line-oriented protocol parser and dispatcher.

---

## 1. Data Representation

### Tiles and Hands

- **`TileKind = int` (`0..33`)**: Dense integer index for the 34 tile kinds:
  - `0..8` = `1m..9m`, `9..17` = `1p..9p`, `18..26` = `1s..9s`, `27..33` = `1z..7z` (E, S, W, N, haku, hatsu, chun).
  - Suit is `k // 9` (`0..3`), rank within suit is `k % 9` (`0..8` for suited, `0..6` for honors).
- **`Tile`** (`@dataclass(frozen=True, slots=True)`): `(kind: int, is_red: bool = False)`. Preserves red fives (`0m`, `0p`, `0s`) for aka dora counting and `legal` actions. Its canonical sort key is `(kind, 0 if is_red else 1)`, placing `0` immediately before `5`.
- **`Counts = tuple[int, ...]` (or mutable `list[int]` internally)**: Length-34 count vector with red fives folded into their kind (`4, 13, 22`). Almost all combinatorial logic (decomposition, shanten, waits, pattern checks) operates directly on these 34-element arrays.

### Melds

- **`MeldKind(Enum)`**: `CHI`, `PON`, `KAN` (daiminkan), `KAKAN` (shouminkan), `ANKAN` (closed kan).
- **`Meld`** (`@dataclass(frozen=True, slots=True)`): `(kind: MeldKind, tiles: tuple[Tile, ...])`, with helper properties `is_open` (`kind is not MeldKind.ANKAN`), `is_kan`, `is_triplet`, `base_kind`, and `aka_count`.
- `hand` never includes meld tiles; `num_melds = len(melds)` determines how many concealed sets (`4 - num_melds`) are needed.

---

## 2. Hand Decomposition (`decompose.py`)

A concealed group is represented as `Group = tuple[int, GroupKind]` where `GroupKind(IntEnum)` defines `PAIR = 0`, `SEQ = 1`, `TRIPLET = 2`, paired with its starting `TileKind`.

This choice aligns directly with the `agari` canonical sort order: sorting groups by `(start_kind, group_kind)` naturally orders by suit (`m, p, s, z`), then first digit, then `pair < sequence < triplet`.

- **Standard decomposition**: Iterate over every `pair_kind` with `counts[pair_kind] >= 2`, subtract 2, and recursively extract `4 - num_melds` sets from the lowest index `i` with `counts[i] > 0`:
  - Try taking a triplet at `i` if `counts[i] >= 3` (only if we haven't already branched into a sequence at `i` in this path, avoiding duplicate permutations).
  - Try taking a sequence `(i, i+1, i+2)` if `i < 27`, `i % 9 <= 6`, and all three counts are `>= 1`.
  - Collect sorted `tuple[Group, ...]` into a `set` to deduplicate identical forms.
- **Chiitoitsu** (`num_melds == 0`): Exactly 7 kinds with `counts[k] == 2` (automatically rejects 4-of-a-kind).
- **Kokushi** (`num_melds == 0`): All 13 yaochu kinds have `counts[k] >= 1` and total tiles is 14.

---

## 3. Structural Shanten and Waits (`shanten.py`)

- **Chiitoi**: `6 - pairs + max(0, 7 - kinds)` where `pairs = count(c >= 2)` and `kinds = count(c >= 1)`.
- **Kokushi**: `13 - distinct_yaochu - (1 if any_yaochu_pair else 0)`.
- **Standard (`std`)**: `min(8 - 2*sets - min(taatsu, 4 - sets) - head)` ignoring tile availability.
  - Because the three numbered suits and honors are independent, we factor the search by suit.
  - For a single 9-tile suit tuple `s`, a memoized (`@lru_cache`) recursive solver `suit_mt(s)` returns a compact tuple of `(sets, max_taatsu)` pairs (at most 5 entries, one per reachable `sets` count).
  - For each of the 4 groups (3 suits + honors), we compute both the no-head `(sets, max_taatsu)` profile and the with-head profile (trying each `i` with `s[i] >= 2` as the pair). Combining across the 4 groups is a tiny nested loop over at most `5^4` states (typically much smaller), giving exact structural shanten at high speed.
- **Waits**:
  - `structural_waits(counts, num_melds)` tests all 34 kinds `k` for whether adding `k` lowers `min_shanten` (or reaches `-1` for tenpai).
  - The `waits` op filters to kinds with `4 - held[k] > 0` (where `held` sums hand + meld tiles) and sums the remaining copies.

---

## 4. Yaku, Fu, and Interpretation Choice (`yaku.py`)

### Win Context and Interpretations

For a standard decomposition `(pair_kind, concealed_sets)`, the winning tile `win_kind` may complete any distinct concealed group containing it:
- The pair → **tanki** wait (`+2 fu`); all concealed triplets remain concealed.
- A concealed triplet → **shanpon** wait (`+0 fu`); on `ron`, that triplet is marked open (`minkou`) for both fu and `sanankou`/`suuankou`.
- A concealed sequence `(s, s+1, s+2)` → **kanchan** (`win == s+1`, `+2 fu`), **penchan** (`12+3` or `89+7`, `+2 fu`), or **ryanmen** (`+0 fu`).

Each `(decomposition, wait_group)` yields a `HandView` dataclass exposing precomputed facts (`is_closed`, `all_sets`, `concealed_triplets`, `kans`, `pair_kind`, `wait_type`, `all_kinds`, `total_counts`, `by`, `seat`, `round`, `flags`).

For `tenhou`, we evaluate all distinct tile kinds present in the 14 tiles as candidate `win_kind` and pick the overall best score.

### Declarative Yaku & Yakuman Table

Yakuman and standard yaku are declared as tables of `Rule(name, check)` entries so each rule reads directly like its specification in `spec/rules.md`:

- **Yakuman rules** return their multiplier (`0`, `1`, or `2` for the four Mahjong Soul double yakuman: `suuankou_tanki`, `kokushi_13`, `junsei_chuuren`, `daisuushii`). If any yakuman fires, regular yaku and dora are ignored and multipliers sum.
- **Standard yaku rules** return their han value (`0` if absent, or closed/open han). Mutual exclusions (`ryanpeikou` vs `iipeikou`, `junchan` vs `chanta`, `chinitsu` vs `honitsu`) are expressed directly in the predicates.
- Dora (`dora`, `aka`, `ura`, with `ura` gated on `riichi`/`double_riichi`) are added only after confirming at least one non-dora yaku exists.

### Fu, Payment, and Tie-Breaking

- **Fu**: Fixed `20` for `pinfu + tsumo`, fixed `25` for `chiitoi`, minimum `30` for open 0-extra-fu `ron`; otherwise `20 + menzen_ron(10) + tsumo(2) + sets_fu + pair_fu(2 per yakuhai, 4 for double wind) + wait_fu`, rounded up to the next 10.
- **Payment**: `basic = min(2000, fu * 2^(2 + han))` below 5 han (no kiriage mangan); limit tiers 5→2000, 6–7→3000, 8–10→4000, 11–12→6000, 13+→8000 (kazoe 1x, printed with real han/fu); real yakuman `8000 * N`. Per-payer amounts rounded up to 100, then honba added (`+300` ron, `+100` per payer tsumo).
- **Choice**: Among all valid interpretations (standard + chiitoi + kokushi), choose highest `(total, is_real_yakuman, han, fu)`, breaking any remaining tie by lexicographically smallest `yaku` string.

---

## 5. How `legal` Reuses the Rest (`legal.py`)

`legal` introduces no duplicate scoring or hand-shape logic:

- **`tsumo` and `ron`**: Call `score_hand(...)` directly (with `riichi` injected into flags when `riichi=1`). `ankan_rob` short-circuits to `is_kokushi(...)`.
- **`riichi:<tile>`**: For each distinct discard, calls `shanten` and `waits` on the 13-tile remainder, requiring `shanten == 0` and `waits.count > 0`.
- **`ankan:<kind>` in riichi**: Compares `structural_waits(before_draw)` against `structural_waits(after_ankan)` (only for `draw.kind`).
- **Kuikae**: A single helper `kuikae_forbidden(meld_kind, took_kind, meld_base)` serves both `called=` (filtering discards) and `discard=` (rejecting dead-end `chi:` calls that would leave no legal discard).
