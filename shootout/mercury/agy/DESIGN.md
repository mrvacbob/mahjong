# Design: Riichi Mahjong Engine in Mercury

## 1. Data Representation

### Tiles and Tile Kinds

We separate **tile kind** (the 34 equivalence classes used for hand shape, shanten, waits, yaku, and fu) from **physical tile** (which distinguishes red fives `0m`, `0p`, `0s` for aka dora and `legal` action reporting):

```mercury
:- type num_suit ---> m ; p ; s.
:- type wind     ---> east ; south ; west ; north.
:- type dragon   ---> haku ; hatsu ; chun.

:- type tile_kind
    --->    num(num_suit, int)      % rank 1..9
    ;       wind(wind)
    ;       dragon(dragon).

:- type is_red ---> red ; plain.

:- type tile
    --->    tile(
                kind   :: tile_kind,
                is_red :: is_red
            ).
```

Because Mercury's standard term ordering (`compare/3`) orders constructors by their declaration order:
- `m < p < s` and `num < wind < dragon`
- `east < south < west < north` and `haku < hatsu < chun`
- `red < plain`

standard term comparison on `tile_kind` and `tile` matches the spec's canonical `mpsz` order (with `0` sorting immediately before `5`) without custom comparator boilerplate.

### Melds

```mercury
:- type meld_type
    --->    chi
    ;       pon
    ;       daiminkan
    ;       shouminkan
    ;       ankan.

:- type meld
    --->    meld(
                meld_type  :: meld_type,
                meld_tiles :: list(tile)
            ).
```

A hand is closed iff every meld in `melds` has `meld_type = ankan`. Every meld contributes a fixed group (sequence, triplet, or kan) and counts toward total tiles (including all 4 tiles of a kan for dora/aka/ura counting and tile-availability in `waits`).

### `bag` (Multiset) vs `set`

Mercury's standard library provides both `bag(T)` (multiset) and `set(T)` (ordered deduplicated set). We use each where its mathematical semantics match the domain:

- **`bag(tile_kind)`** is used for **concealed hands** during hand decomposition (`agari`), **all tiles** when counting multiplicity (e.g., tile availability in `waits`, kokushi/chuuren checks, quad detection for `ankan`), and **dora/ura indicators** (where duplicate indicators count multiple times, so a `set` would be wrong).
- **`set(tile_kind)`** is used for **wait kinds** (mathematical set of winning tile kinds; in `legal`, riichi ankan wait-preservation is direct set equality `WaitsBefore = WaitsAfter`), **kuikae-forbidden kinds**, **distinct terminal/honor kinds** for `kyuushu`, and **distinct tile kinds** in chiitoi.
- **`set(tile)`** (or sorted deduplicated `list(tile)`) is used for distinct physical discard/riichi/kakan targets, where `0m` and `5m` are distinct elements.
- **`list(string)`** via `list.sort_and_remove_dups` / `solutions.solutions` is used for canonical sorted string output (`forms`, `actions`, `yaku`).

## 2. Hand Decomposition (`agari`)

Standard 4-meld + 1-pair decomposition is expressed directly as a **`nondet`** relational predicate over `bag(tile_kind)`:

```mercury
:- pred decompose_std(bag(tile_kind)::in, tile_kind::out, list(group)::out) is nondet.
```

1. Nondeterministically choose a `Pair` with count `>= 2` in the concealed `bag(tile_kind)` and remove 2 copies.
2. Recursively partition the remaining bag into concealed `group`s (`seq(num_suit, int)` or `triplet(tile_kind)`):
   - Take the smallest remaining tile kind `MinK` in the bag (`bag.least_value` or via `bag.to_assoc_list` head).
   - Either remove 3 copies of `MinK` as `triplet(MinK)`, or (if `MinK = num(S, N)` with `N =< 7`) remove `num(S, N)`, `num(S, N+1)`, `num(S, N+2)` as `seq(S, N)`.
   - To avoid generating both `[seq(S, N), triplet(num(S, N))]` and `[triplet(num(S, N)), seq(S, N)]` when 4 copies of `MinK` are present, we disallow picking `seq` for a tile once a `triplet` for that exact tile has been chosen.
3. `solutions.solutions/2` collects all valid decompositions into a sorted, deduplicated list.

Special forms (`chiitoi` and `kokushi`) are checked deterministically on the concealed bag when `melds = []`. A hand can yield both standard forms and `chiitoi` (e.g. ryanpeikou shapes). Groups within each form are ordered by suit, first digit, then `pair < seq < triplet`, and forms are sorted as strings.

## 3. Shanten and Waits (`shanten`)

- **Standard shanten** (`8 - 2*sets - taatsu - head`, `sets + taatsu <= 4 - num_melds`): Computed suit-by-suit (3 numbered suits + honors). For each suit, a small recursive search computes the Pareto-optimal `(sets, max_taatsu)` table both without a head and with a head extracted from that suit. Combining the 4 suit tables is exact (including 4-of-a-kind hands where a quad can split into head + taatsu or triplet + lone tile) and avoids whole-hand backtracking.
- **Chiitoi shanten** (when `melds = []`): `6 - pairs + max(0, 7 - kinds)`, counting 4-of-a-kind as 1 pair.
- **Kokushi shanten** (when `melds = []`): `13 - yaochuu_kinds - (if has_yaochuu_pair then 1 else 0)`.
- **Waits**: Test adding each of the 34 tile kinds to the 13-tile hand.
  - For the `waits` op and `riichi` tenpai check: only kinds with `< 4` copies in `hand + melds` are included, summing remaining copies (`4 - count`).
  - For riichi `ankan` wait comparison: structural waits over all 34 kinds (checking which kinds make `agari` true), returning `set(tile_kind)`.

## 4. Scoring, Yaku, Fu, and Interpretation Choice (`score`)

### Wait Assignment and Interpretation Enumeration

Given `(hand, melds, win, by, ctx)`:
- If `tenhou` is in `flags`, nondeterministically choose any of the 14 tiles as `win` (leaving the other 13 as `hand`); otherwise use the supplied `win`.
- Enumerate all complete interpretations (`nondet`):
  - `interp_kokushi(Is13Wait)`
  - `interp_chiitoi`
  - `interp_std(Pair, GroupsWithOpenFlag, WaitType)`: nondeterministically assign `win` to the pair (`tanki`), a concealed triplet (`shanpon` — marked open if `by = ron`), or a concealed sequence (`ryanmen`, `kanchan`, or `penchan`).

### Yaku Declaration

Each yaku is a small, self-contained predicate over the interpretation and `score_context`, directly mirroring `spec/rules.md`:
- **Yakuman** are checked first (`semidet` predicates collected into `list(yaku_entry)`). `kokushi_13`, `suuankou_tanki`, `junsei_chuuren`, and `daisuushii` contribute `2`; all others contribute `1`. Distinct yakuman stack by summing multiples. If any yakuman applies, regular yaku and dora are ignored.
- **Standard yaku** are evaluated on the interpretation (respecting closed-only yaku, open-han reductions, and mutual exclusions like `ryanpeikou` vs `iipeikou`, `junchan` vs `chanta`, `chinitsu` vs `honitsu`). If no real yaku applies, the interpretation fails (`no_yaku`). Otherwise `dora`, `aka`, and (if `riichi` or `double_riichi`) `ura` are added.

### Fu and Payment

- `chiitoi`: fixed `25` fu.
- `pinfu` + `tsumo`: fixed `20` fu.
- Open hand with `0` extra fu on `ron`: fixed `30` fu.
- Otherwise: `20` base + menzen ron (`10`) + tsumo (`2`) + group fu (open/closed, simple/yaochuu, triplet/kan) + pair fu (`2` for dragon or single wind, `4` for double wind) + wait fu (`2` for kanchan/penchan/tanki), rounded up to the next multiple of `10`.
- Basic points: `fu * 2^(2 + han)` capped at `2000` (mangan) for `< 5` han (no kiriage mangan); limit tiers `2000 / 3000 / 4000 / 6000 / 8000` (kazoe capped at 1x `8000`), `8000 * N` for N-tuple yakuman.
- Best interpretation is chosen by comparing `(Total, IsRealYakuman, Han, Fu, NegatedYakuString)` using a total `det` comparator.

## 5. Legal Actions (`legal`)

`legal` directly reuses `agari`, `shanten`, `waits`, and `score`:
- **Win legality (`tsumo` / `ron`)**: delegates to `score.has_valid_win/7` (with `riichi=1` injecting `riichi` into flags; for `ankan_rob`, only `kokushi` is checked).
- **Riichi**: closed hand, not in riichi, `wall >= 4`, and for each distinct physical tile `T` in `hand + draw`, `waits.live_waits(HandWithoutT, Melds)` has `shanten = 0` and `count > 0`.
- **Ankan**: `wall >= 1`, `kans < 4`, 4 copies of kind `K` in `hand + draw`. In riichi, additionally `K = Draw.kind` (no okurikan) and `waits.structural_waits(HandBeforeDraw, Melds) = waits.structural_waits(HandAfterAnkan, [Ankan | Melds])`.
- **Kakan**: not in riichi, `wall >= 1`, `kans < 4`, holding a tile matching an existing `pon` in `melds`.
- **Kuikae & dead-end chi**: `kuikae_forbidden(Meld, TookKind) = set(tile_kind)` computes the forbidden kinds (called kind, plus opposite-end suji for ryanmen chi). Used both in the `called` state to filter `discard:` and in the `discard` state to reject dead-end `chi:` calls that leave no legal discard.

## 6. Main Predicate Determinism Declarations

```mercury
% tiles.m
:- pred parse_tile(string::in, tile::out) is semidet.
:- pred parse_tile_list(string::in, list(tile)::out) is semidet.
:- pred parse_meld(string::in, meld::out) is semidet.
:- func next_dora(tile_kind) = tile_kind.                     % det

% agari.m
:- pred decompose_std(bag(tile_kind)::in, tile_kind::out, list(group)::out) is nondet.
:- func all_agari_forms(bag(tile_kind), list(meld)) = list(agari_form).  % det
:- pred is_agari(bag(tile_kind)::in, list(meld)::in) is semidet.

% shanten.m
:- func compute_shanten(bag(tile_kind), list(meld)) = shanten_result.    % det
:- func compute_waits(list(tile), list(meld)) = waits_result.            % det
:- func structural_waits(bag(tile_kind), list(meld)) = set(tile_kind).   % det

% score.m
:- pred eval_score(list(tile)::in, list(meld)::in, tile::in, win_by::in,
    score_context::in, score_outcome::out) is det.
:- pred can_win_with_yaku(list(tile)::in, list(meld)::in, tile::in, win_by::in,
    score_context::in) is semidet.

% legal.m
:- func legal_actions(legal_req) = list(string).              % det

% mj.m
:- pred main(io::di, io::uo) is det.
```
