-- | Shape analysis of concealed tiles: complete decompositions, shanten, waits.
--
-- Everything works suit by suit on a list of per-number counts, so "a run
-- starts here" is the list pattern @c : b : d : rest@.
{-# LANGUAGE LambdaCase #-}
module Hand
  ( decompose, isChiitoi, isKokushi, structuralWaits
  , Shanten (..), shanten, minShanten
  , liveWaits, copiesLeft
  ) where

import Tile
import Meld
import Data.List (sortOn)
import Data.Maybe (catMaybes)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Control.Monad.State.Strict (evalState, gets, modify)

-- | Per-number counts of one suit: 9 entries (7 for honors).
suitCounts :: M.Map Kind Int -> Suit -> [Int]
suitCounts m s = [M.findWithDefault 0 (Kind s n) m | n <- numbers s]

tally :: [Kind] -> M.Map Kind Int
tally ks = M.fromListWith (+) [(k, 1) | k <- ks]

------------------------------------------------------------------------------
-- Complete hands

-- | Every way to split the concealed kinds into sets and exactly one pair,
-- each form's groups in print order (suit, first number, pair<run<triplet).
decompose :: [Kind] -> [[Group]]
decompose ks =
  [ sortOn (\g -> (gbase g, gform g)) gs
  | gs <- concat <$> mapM perSuit [minBound .. maxBound]
  , count ((== Pair) . gform) gs == 1 ]
  where
    m = tally ks
    perSuit s = suitGroups s 1 False (suitCounts m s)

-- | Complete groups within one suit, with at most one pair (the Bool: a pair
-- is already taken). Always consumes the lowest remaining tile first, so each
-- split is found once.
suitGroups :: Suit -> Int -> Bool -> [Int] -> [[Group]]
suitGroups _ _ _ [] = [[]]
suitGroups s n paired (0 : xs) = suitGroups s (n + 1) paired xs
suitGroups s n paired (c : xs) = triplet ++ run ++ pair
  where
    here f paired' rest = (Group f (Kind s n) False :) <$> suitGroups s n paired' rest
    triplet = [g | c >= 3, g <- here Triplet paired (c - 3 : xs)]
    run = case xs of
      b : d : ys | s /= Honor, b > 0, d > 0 -> here Run paired (c - 1 : b - 1 : d - 1 : ys)
      _ -> []
    pair = [g | c >= 2, not paired, g <- here Pair True (c - 2 : xs)]

-- | Seven distinct pairs (four of a kind is not two pairs). Needs 14 concealed
-- tiles, so never holds with a meld.
isChiitoi :: [Kind] -> Bool
isChiitoi ks = length ks == 14 && all (== 2) (M.elems (tally ks))

isKokushi :: [Kind] -> Bool
isKokushi ks = length ks == 14 && all isYaochu ks && M.size (tally ks) == 13

-- | The kinds that complete the concealed tiles. Availability is ignored, so a
-- fifth copy of a held kind counts (the riichi ankan rule compares these,
-- "structural, as in @shanten@").
structuralWaits :: [Kind] -> [Kind]
structuralWaits ks = [k | k <- allKinds, complete (k : ks)]
  where complete h = not (null (decompose h)) || isChiitoi h || isKokushi h

-- | Copies of a kind not among the tiles already seen.
copiesLeft :: [Kind] -> Kind -> Int
copiesLeft seen k = 4 - countOf k seen

------------------------------------------------------------------------------
-- Shanten

-- | (sets, partial sets, pair) reachable within one suit.
type Partial = (Int, Int, Int)

-- | Keep only tuples not dominated by another with the same pair count.
-- The shanten score is monotone in sets and partials, so this loses nothing.
prune :: [Partial] -> [Partial]
prune xs = [x | x <- uniq, not (any (`dominates` x) uniq)]
  where
    uniq = S.toList (S.fromList xs)
    dominates (s', t', h') (s, t, h) = h' == h && s' >= s && t' >= t && (s', t') /= (s, t)

-- | The ways to take one partial or complete group off the lowest number, or to
-- give up on that number (its remaining tiles stay isolated).
moves :: Suit -> [Int] -> [(Partial, [Int])]
moves _ [] = []
moves s (c : xs) = concat
  [ [((1, 0, 0), c - 3 : xs) | c >= 3]                                          -- triplet
  , [((1, 0, 0), c - 1 : b - 1 : d - 1 : ys) | numbered, b : d : ys <- [xs], b > 0, d > 0] -- run
  , [((0, 0, 1), c - 2 : xs) | c >= 2]                                          -- pair as head
  , [((0, 1, 0), c - 2 : xs) | c >= 2]                                          -- pair as partial
  , [((0, 1, 0), c - 1 : b - 1 : ys) | numbered, b : ys <- [xs], b > 0]         -- 34
  , [((0, 1, 0), c - 1 : b : d - 1 : ys) | numbered, b : d : ys <- [xs], d > 0] -- 35
  , [((0, 0, 0), xs)]                                                           -- give up on c
  ]
  where numbered = s /= Honor

-- | Every (Pareto-best) outcome for one suit; memoised on the remaining counts.
suitPartials :: Suit -> [Int] -> [Partial]
suitPartials s counts = evalState (go counts) M.empty
  where
    go [] = pure [(0, 0, 0)]
    go (0 : xs) = go xs
    go cs = gets (M.lookup cs) >>= \case
      Just r -> pure r
      Nothing -> do
        r <- prune . concat <$> mapM step (moves s cs)
        modify (M.insert cs r)
        pure r
    step (d, rest) = do
      ps <- go rest
      pure [add d p | p <- ps, pairOf d + pairOf p <= 1]
    pairOf (_, _, h) = h
    add (a, b, c) (x, y, z) = (a + x, b + y, c + z)

-- | Outcomes per suit, in suit order.
suitTables :: M.Map Kind Int -> [[Partial]]
suitTables m = [suitPartials s (suitCounts m s) | s <- [minBound .. maxBound]]

-- | Standard-form shanten: 8 − 2·sets − partials − pair, sets + partials ≤ 4,
-- with the declared melds counted as sets.
fromTables :: Int -> [[Partial]] -> Int
fromTables melds tables = 8 - maximum (map value (foldl' combine [(melds, 0, 0)] tables))
  where
    combine as bs = prune [(s1 + s2, t1 + t2, h1 + h2) | (s1, t1, h1) <- as, (s2, t2, h2) <- bs, h1 + h2 <= 1]
    value (s, t, h) = 2 * s + min t (4 - s) + h

-- | Shanten of each form. Chiitoi and kokushi exist only without melds.
data Shanten = Shanten { stdShanten :: Int, chiitoiShanten :: Maybe Int, kokushiShanten :: Maybe Int }

minShanten :: Shanten -> Int
minShanten sh = minimum (stdShanten sh : catMaybes [chiitoiShanten sh, kokushiShanten sh])

shanten :: Int -> [Kind] -> Shanten
shanten melds ks = withTables melds (suitTables (tally ks)) ks

withTables :: Int -> [[Partial]] -> [Kind] -> Shanten
withTables melds tables ks = Shanten (fromTables melds tables) (special chiitoi) (special kokushi)
  where
    special v = if melds == 0 then Just v else Nothing
    -- 6 − pairs + max(0, 7 − kinds)
    chiitoi = 6 - count (>= 2) cs + max 0 (7 - length cs)
      where cs = M.elems (tally ks)
    -- 13 − terminal/honor kinds − (1 if one of them is paired)
    kokushi = 13 - length ys - (if any (>= 2) ys then 1 else 0)
      where ys = M.elems (tally (filter isYaochu ks))

-- | The @waits@ op: min shanten, the kinds whose draw lowers it that have a
-- copy left outside the given tiles (hand and melds), and how many copies.
liveWaits :: Int -> [Kind] -> [Kind] -> (Int, [Kind], Int)
liveWaits melds ks seen = (now, live, sum (map (copiesLeft seen) live))
  where
    m = tally ks
    tables = suitTables m
    now = minShanten (withTables melds tables ks)
    live = [k | k <- allKinds, copiesLeft seen k > 0, after k < now]
    -- Drawing k only changes k's suit, so only that suit is searched again.
    after k =
      let s = suit k
          table' = suitPartials s (suitCounts (M.insertWith (+) k 1 m) s)
          tables' = [if s' == s then table' else t | (s', t) <- zip [minBound ..] tables]
       in minShanten (withTables melds tables' (k : ks))
