# Swift Riichi Mahjong Engine — Design

## 1. Data Representation

The engine models mahjong primitives with small, stack-allocated Swift value types (`struct` and `enum`, all `Sendable`, `Hashable`, and `Comparable`).

- **`Suit`** (`enum Suit: UInt8, CaseIterable, Comparable`): `.man` (`m`), `.pin` (`p`), `.sou` (`s`), `.honor` (`z`), ordered canonically `m < p < s < z`.
- **`TileKind`** (`struct TileKind: RawRepresentable, Comparable, Hashable`): wraps a `UInt8` in `0..<34` (`0...8` man, `9...17` pin, `18...26` sou, `27...30` winds E/S/W/N, `31...33` dragons white/green/red). Computes properties directly from `rawValue`: `suit`, `rank`, `isTerminal`, `isHonor`, `isYaochu`, `isSimple`, `isGreen`, and `doraNext` (wrapping 9→1, N→E, red→white).
- **`Tile`** (`struct Tile: Comparable, Hashable`): pairs `kind: TileKind` with `isRed: Bool`. `Comparable` orders by `kind` ascending, then `isRed == true` before `false`, which directly implements the spec's canonical tile-list ordering (`0` sorts immediately before `5`, and `4 < 0 < 5 < 6`).
- **`TileCounts`** (`struct TileCounts: Equatable, Hashable`): a fixed-size 34-byte value type backed by `InlineArray<34, UInt8>` (Swift 6.2+/6.4 stack-allocated fixed-capacity array, zero heap allocations). Supports subscripting by `TileKind`, total tile count, distinct-kind count, and suit-local indexing.
- **`HandTiles`** (`struct HandTiles: Equatable`): pairs `counts: TileCounts` with a 3-bit `redMask: UInt8` (one bit per numbered suit for `0m`, `0p`, `0s`). Because at most one red five exists per suit, `(counts, redMask)` losslessly represents an exact multiset of tiles including red fives, while keeping all decomposition and shanten math operating directly on `TileCounts`.
- **`Meld`** (`struct Meld: Equatable, Hashable`): stores `kind: MeldKind` (`.chi`, `.pon`, `.daiminkan`, `.shouminkan`, `.ankan`), `baseKind: TileKind`, and `tiles: [Tile]` (preserving red fives for aka dora). Derived properties distinguish `isOpen` (`kind != .ankan`) from `isClosed` (`kind == .ankan`), `isKan`, `isSequence`, and `isTripletOrKan`.
- **`Group`** (`struct Group: Comparable, Hashable`): represents a concealed group in a decomposition with `kind: GroupKind` (`.pair = 0`, `.sequence = 1`, `.triplet = 2`) and `base: TileKind`. `Comparable` orders by `base` (suit, then first digit) and then `kind` (pair < sequence < triplet), directly matching the `agari` output specification.

## 2. Hand Decomposition (`agari`)

`decompose(counts:meldCount:)` produces all valid winning structures for a `14 - 3k` concealed hand:

1. **Standard 4-sets + 1-pair**: iterates over each `TileKind` with `counts[k] >= 2` as the pair, then recursively extracts `4 - k` sets from the remaining counts by always consuming the lowest-indexed non-zero tile `t` first (branching on triplet `t,t,t` if `counts[t] >= 3` and sequence `t,t+1,t+2` if `t` is numbered with `rank <= 7` and `counts[t+1] > 0 && counts[t+2] > 0`). Sorting each resulting `[Group]` and deduplicating guarantees canonical, duplicate-free standard forms.
2. **Chiitoitsu** (`meldCount == 0`): true when exactly 7 distinct kinds have count 2 (4 of a kind is rejected).
3. **Kokushi Musou** (`meldCount == 0`): true when all 13 yaochu kinds have count ≥ 1 and total count is 14.

## 3. Shanten and Waits (`shanten`, `waits`)

- **Chiitoi shanten** (`meldCount == 0`): `6 - pairs + max(0, 7 - kinds)` where `pairs` counts kinds with `count >= 2` and `kinds` counts kinds with `count >= 1`.
- **Kokushi shanten** (`meldCount == 0`): `13 - uniqueYaochu - (hasYaochuPair ? 1 : 0)`.
- **Standard shanten (`std`)**: exploits the independence of the four suits (`m`, `p`, `s`, `z`). For each suit, a small recursive search computes two 5-element arrays (`maxTaatsuNoHead[sets]` and `maxTaatsuWithHead[sets]`, for `sets` in `0...4`) giving the maximum partial sets (pairs, ryanmen/penchan, kanchan) achievable alongside `sets` complete sets. Combining the four suits with `meldCount` existing melds finds the minimum `8 - 2 * sets - min(taatsu, 4 - sets) - head` over all valid splits. This is exact (including 4-of-a-kind hands where shanten ignores tile availability) and runs in microseconds with zero heap allocations.
- **Waits (`waits`)**: computes `base = minShanten(hand, melds)`, then tests adding each of the 34 kinds `t` that has `remaining = 4 - used(t) > 0`; if `minShanten(hand + t, melds) < base`, `t` is a wait and adds `remaining` to `count`. A variant without the `remaining > 0` filter provides structural waits for the riichi-ankan check in `legal`.

## 4. Yaku, Fu, and Interpretation Choice (`score`)

For a winning hand (`hand` + `win` + `melds`), `score` expands every decomposition into concrete `HandInterpretation` values:

- A **standard** decomposition expands into one interpretation per distinct concealed group that could have been completed by `win.kind` (pair → `tanki`; triplet → `shanpon`, where `by == .ron` marks that triplet open for both fu and `sanankou`/`suuankou`; sequence → `kanchan`, `penchan`, or `ryanmen` depending on `win.kind`'s position in the sequence).
- **Chiitoitsu** and **Kokushi** each produce their own interpretation variant (`chiitoi`, `kokushi(is13Wait:)`).
- When `flags` contains `tenhou`, the engine evaluates all distinct tile kinds present in the 14-tile hand as candidate winning tiles and takes the best overall score, automatically upgrading eligible hands to `kokushi_13`, `suuankou_tanki`, or `junsei_chuuren`.

**Yaku declarations**: Yakuman and regular yaku are declared in static tables (`yakumanRules: [YakumanRule]` and `yakuRules: [YakuRule]`). Each rule pairs its spec name, han or yakuman multiple (closed/open), and a predicate closure `(ScoreContext, HandInterpretation) -> Bool` written directly in terms of domain properties (`interp.allSets.allSatisfy(\.isTripletOrKan)`, `interp.concealedTripletCount == 3`, `interp.allTiles.allSatisfy(\.isSimple)`, etc.). If any yakuman rule matches, regular yaku and dora are skipped and yakuman multiples sum. Otherwise, if at least one regular yaku matches, `dora`, `aka`, and (when riichi/double_riichi) `ura` are appended.

**Fu and payment**:
- `chiitoi` is fixed 25 fu; `pinfu && tsumo` is fixed 20 fu; otherwise base 20 + menzen ron (+10) / tsumo (+2) + set fu + pair fu (+2 per dragon/seat/round, giving +4 for double wind) + wait fu (+2 for kanchan/penchan/tanki), with open no-fu ron bumped to 30, rounded up to a multiple of 10.
- Basic points follow the Mahjong Soul table (no kiriage mangan, kazoe yakuman capped at 1x, natural double yakuman 2x, stacking yakuman).
- **Interpretation choice**: candidates are compared by a strict total order: highest `total`, then real yakuman over kazoe yakuman, then higher `han`, then higher `fu`, then lexicographically smallest `yaku` string.

## 5. Legal Actions (`legal`)

`legal` directly reuses `score`, `waits`, `agari`, and `HandTiles`:
- **`called` + `took`**: computes the 1 or 2 kuikae-forbidden `TileKind`s from the called meld and emits `discard:<tile>` for each distinct non-forbidden tile in `hand`.
- **`draw`**: checks `tsumo` via `score` (passing `riichi` flag if `riichi=1`); in riichi emits only `discard:<draw>` plus `ankan:<draw.kind>` when `wall >= 1`, `kans < 4`, 4 copies are held, and structural waits before the draw equal structural waits after the ankan. Outside riichi emits all distinct `discard:<tile>`, `riichi:<tile>` when closed, `wall >= 4`, and `waits(hand - tile)` has `shanten == 0 && count > 0`, plus `ankan`, `kakan`, and `kyuushu` (`first=1`, ≥9 distinct yaochu kinds).
- **`discard` + `from`**: always emits `pass`. For `ankan_rob`, allows `ron` only if `furiten=0` and the hand completes kokushi. For `chankan`, allows `ron` only if `furiten=0` and `score` succeeds. For normal discards, checks `ron` via `score` (when `furiten=0`), and when `riichi=0 && wall >= 1` generates `kan`, `pon` (red/plain variants), and `chi` (kamicha only, red/plain variants, filtered to exclude kuikae dead-ends where no legal discard would remain).
