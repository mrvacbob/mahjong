# Haskell Riichi Mahjong Engine — Design

## Overview & Module Structure

The implementation lives under `shootout/haskell/agy/src/` and uses only GHC 9.14 boot packages (`base`, `array`, `containers`, `bytestring`). It is compiled with `ghc --make -O2` via `build.sh` into `./mj`.

Modules:
- `Tile.hs`: `Suit`, `Wind`, `TileKind` (0–33), `Tile` (kind + red flag), `Meld`, parsing and canonical formatting in `mpsz` notation, dora successor, and 34-element unboxed count arrays (`Counts`).
- `Agari.hs`: Hand decomposition (`agari`) for standard 4-meld+pair, `chiitoi`, and `kokushi`, plus structural wait enumeration.
- `Shanten.hs`: Structural `shanten` (standard, chiitoi, kokushi) via per-suit DP/search, and `waits` (live-tile filtering and count).
- `Score.hs`: `HandShape` / `WaitType` enumeration, declarative yaku and yakuman tables, fu calculation, limit/payment arithmetic, honba, tenhou best-tile selection, and tie-breaking.
- `Legal.hs`: Legal action generation for `draw`, `discard` (including `chankan` and `ankan_rob`), and `called` (kuikae), reusing `Agari`, `Shanten`, `Waits`, and `Score`.
- `Main.hs`: Line-oriented `ByteString` request parser, dispatcher for the five ops, and response formatter.

## Data Representation

### Tiles and Tile Kinds

```haskell
data Suit = Man | Pin | Sou | Honor
  deriving (Eq, Ord, Enum, Bounded, Show)

newtype TileKind = TileKind { unKind :: Int }
  deriving (Eq, Ord, Ix, Show)
  -- 0..8: 1m..9m, 9..17: 1p..9p, 18..26: 1s..9s, 27..30: 1z..4z (E S W N), 31..33: 5z..7z (W G R)

data Tile = Tile
  { tileKind :: !TileKind
  , tileRed  :: !Bool
  } deriving (Eq, Show)
```

`Ord Tile` compares `tileKind` first, then `tileRed` with `True < False`. This places `0m` immediately before `5m` (and `4m < 0m < 5m < 6m`), matching the spec's canonical order everywhere—tile lists, `chi:40m`/`chi:07m`, `pon:05m`, and `discard:0m`.

### Hands and Melds

- **Exact hand**: `[Tile]` (preserves red fives for aka dora and `legal` actions).
- **Kind multiset**: `type Counts = UArray Int Int` indexed `0..33`. Used by `agari`, `shanten`, `waits`, and shape checks where red fives are indistinguishable from plain fives.
- **Melds**:
  ```haskell
  data MeldKind = Chi | Pon | Daiminkan | Shouminkan | Ankan
    deriving (Eq, Ord, Show)

  data Meld = Meld
    { meldKind  :: !MeldKind
    , meldTiles :: ![Tile]
    } deriving (Eq, Show)
  ```
  An `Ankan` counts as a meld for shape (`13 - 3k` concealed tiles, disqualifies `chiitoi`/`kokushi`) while keeping the hand closed (`isOpenMeld m = meldKind m /= Ankan`).

## Hand Decomposition (`Agari.hs`)

Concealed groups are represented as:

```haskell
data GroupKind = Pair | Seq | Triplet | Kan
  deriving (Eq, Ord, Show)

data CGroup = CGroup !TileKind !GroupKind
  deriving (Eq, Ord, Show)
```

Because `Pair < Seq < Triplet`, derived `Ord` on `CGroup` directly matches the spec's `agari` group ordering (suit, then first digit, then pair < sequence < triplet).

- **Standard forms**: Pick any `TileKind` with `count >= 2` as the `Pair`, then recursively decompose the remaining tiles into `4 - length melds` sets (`Triplet` or `Seq`) by always consuming the lowest-index remaining tile first. Passing a canonical lower bound avoids duplicate permutations; forms are sorted as strings and deduplicated.
- **Special forms** (only when `null melds`): `chiitoi` requires 7 distinct kinds with count 2; `kokushi` requires all 13 yaochu kinds with count `>= 1` and total 14.

## Shanten and Waits (`Shanten.hs`)

- **Standard shanten**: `8 - 2*sets - min (4 - sets) taatsu - head`, ignoring tile availability (so holding 4 copies of a wait tile still gives `std=0`).
  Because sets, partial sets (`taatsu`), and the pair (`head`) are additive across the four suits, each numbered suit (9 ranks) is analyzed independently to produce two 5-element tables: `noHead[s]` and `withHead[s]` giving the maximum `taatsu` achievable for `s` sets (`0..4`). Honors (7 ranks) are computed directly in O(7). The four suits are combined by small 5-element convolutions (allowing at most one suit to contribute the head) plus `length melds` fixed sets.
- **Chiitoi**: `6 - pairs + max 0 (7 - kinds)` (4-of-a-kind counts as 1 pair, 1 kind).
- **Kokushi**: `13 - yaochuKinds - (if hasYaochuPair then 1 else 0)`.
- **`waits`**: Evaluates `shanten` of the 13-3k hand, then tests adding each of the 34 kinds (only recomputing the affected suit for `std`). Any kind that strictly lowers `min` shanten and has `< 4` copies across hand + melds is included in `tiles`, summing `4 - used` into `count`.

## Yaku, Fu, and Interpretation Choice (`Score.hs`)

To score a winning hand, each decomposition from `Agari` is expanded into concrete `HandShape` interpretations:

```haskell
data WaitType = Ryanmen | Shanpon | Kanchan | Penchan | Tanki
  deriving (Eq, Ord, Show)

data Mentsu = Mentsu
  { mKind :: !GroupKind
  , mTile :: !TileKind
  , mOpen :: !Bool
  } deriving (Eq, Ord, Show)

data HandShape
  = StandardShape { hsPair :: !TileKind, hsMentsu :: ![Mentsu], hsWait :: !WaitType }
  | ChiitoiShape  { hsPairs :: ![TileKind] }
  | KokushiShape  { hs13Wait :: !Bool }
```

For `StandardShape`, the winning tile can complete the pair (`Tanki`), a concealed triplet (`Shanpon`—marked `mOpen = True` when `by == Ron`, which naturally handles both fu and `sanankou`/`suuankou`), or a concealed sequence (`Kanchan`, `Penchan`, or `Ryanmen`).

### Declarative Yaku & Yakuman

Yakuman and standard yaku are expressed as lists of pure predicates `ScoreCtx -> HandShape -> [(String, Int)]`, one entry per rule in `spec/rules.md`:
- **Yakuman**: Checked first per interpretation. Natural double yakuman (`kokushi_13`, `suuankou_tanki`, `junsei_chuuren`, `daisuushii`) emit `:2`; others emit `:1`. Distinct yakuman stack by summing their multipliers. If any yakuman triggers on a shape, ordinary yaku and dora are ignored for that shape.
- **Standard yaku**: Each rule checks openness (`closedOnly` vs open/closed han), situational flags, tile predicates (`tanyao`, `honroutou`, `honitsu`, `chinitsu`), or mentsu patterns (`pinfu`, `iipeikou`/`ryanpeikou`, `sanshoku`, `ittsu`, `chanta`/`junchan`, `sanankou`, `toitoi`, `shousangen`, `sankantsu`, `yakuhai_*`). If at least one real yaku is present, `dora`, `aka`, and (when `riichi`/`double_riichi`) `ura` are added.

### Fu, Payments, and Tie-Breaking

- **Fu**: `ChiitoiShape` is fixed 25 fu; `Pinfu + Tsumo` is fixed 20 fu; open `StandardShape` ron with 0 extra fu is 30 fu; otherwise `20 + menzenRon(10) + tsumo(2) + mentsuFu + pairFu (2 per matching wind/dragon, 4 for double wind) + waitFu(2 for kanchan/penchan/tanki)` rounded up to 10.
- **Payments**: `basic = min 2000 (fu * 2^(2 + han))` below 5 han (no kiriage mangan); limit tiers 2000/3000/4000/6000/8000 for 5/6–7/8–10/11–12/13+ han; `8000 * mult` for yakuman. Individual payments round up to 100, then add honba (+300 ron, +100 per payer tsumo).
- **Tenhou**: When `FlagTenhou` is set, every distinct tile in the 14 concealed tiles is tried as the winning tile, and the best result is chosen.
- **Interpretation choice**: Maximize `(total, isRealYakuman, han, fu, Down yakuString)`.

## Reuse in `Legal.hs`

`Legal.hs` directly reuses the core modules:
- **`tsumo` / `ron`**: Calls `Score.scoreHand` (adding `FlagRiichi` when `riichi=1`) and checks for a valid winning result. For `ankan_rob`, checks `Agari.isKokushi` directly.
- **`riichi:<tile>`**: For each distinct tile in the 14-tile hand, removes it and calls `Shanten.computeWaits`, requiring `shanten == 0 && count > 0`.
- **`ankan:<kind>` in riichi**: Compares `Agari.structuralWaits` before the draw and after moving 4 copies of the drawn kind into an `Ankan` meld.
- **`chi:<two>` / `called`**: Computes kuikae-forbidden kinds from the chi/pon shape; filters `discard:` after `called`, and rejects any `chi:` that would leave zero legal discards.
