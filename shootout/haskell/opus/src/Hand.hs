-- | Shape analysis of concealed tiles: complete decompositions, shanten, waits.
--
-- Everything works suit by suit on a list of per-number counts, so "a run
-- starts here" is the list pattern @c : b : d : rest@.
{-# LANGUAGE LambdaCase #-}
module Hand
  ( decompose, isChiitoi, isKokushi
  , shantenStd, shantenChiitoi, shantenKokushi, shantenMin
  , improving, liveWaits
  , countOf
  ) where

import Tile
import Meld
import Data.List (sortOn)
import qualified Data.Map.Strict as M
import Control.Monad.State.Strict (evalState, gets, modify)

-- | Per-number counts of one suit: 9 entries (7 for honors).
suitCounts :: M.Map Kind Int -> Suit -> [Int]
suitCounts m s = [M.findWithDefault 0 (Kind s n) m | n <- [1 .. size s]]

size :: Suit -> Int
size Honor = 7
size _ = 9

tally :: [Kind] -> M.Map Kind Int
tally ks = M.fromListWith (+) [(k, 1) | k <- ks]

countOf :: Kind -> [Kind] -> Int
countOf k = length . filter (== k)

------------------------------------------------------------------------------
-- Complete hands

-- | Every way to split the concealed kinds into sets and exactly one pair,
-- each form's groups in print order (suit, first number, pair<run<triplet).
decompose :: [Kind] -> [[Group]]
decompose ks = [sortOn (\g -> (gbase g, gform g)) gs | gs <- concat <$> mapM perSuit [minBound .. maxBound], pairs gs == 1]
  where
    m = tally ks
    perSuit s = suitGroups s 1 (suitCounts m s)
    pairs = length . filter ((== Pair) . gform)

-- | Complete groups within one suit, with at most one pair. Always consumes the
-- lowest remaining tile first, so each split is found once.
suitGroups :: Suit -> Int -> [Int] -> [[Group]]
suitGroups _ _ [] = [[]]
suitGroups s n (0 : xs) = suitGroups s (n + 1) xs
suitGroups s n (c : xs) = triplet ++ run ++ pair
  where
    k = Kind s n
    here f rest = (Group f k False :) <$> suitGroups s n rest
    triplet = [g | c >= 3, g <- here Triplet (c - 3 : xs)]
    run = case xs of
      b : d : ys | s /= Honor, b > 0, d > 0 -> here Run (c - 1 : b - 1 : d - 1 : ys)
      _ -> []
    pair = [g | c >= 2, g <- here Pair (c - 2 : xs), countPairs g <= 1]
    countPairs = length . filter ((== Pair) . gform)

-- | Seven distinct pairs (four of a kind is not two pairs).
isChiitoi :: [Kind] -> Bool
isChiitoi ks = length ks == 14 && all (== 2) (M.elems (tally ks))

isKokushi :: [Kind] -> Bool
isKokushi ks = length ks == 14 && all isYaochu ks && M.size (tally ks) == 13

------------------------------------------------------------------------------
-- Shanten

-- | (sets, partial sets, pair) reachable within one suit.
type Partial = (Int, Int, Int)

-- | Keep only tuples not dominated by another with the same pair count.
-- The shanten score is monotone in sets and partials, so this loses nothing.
prune :: [Partial] -> [Partial]
prune xs = [x | x <- uniq, not (any (`dominates` x) uniq)]
  where
    uniq = M.keys (M.fromList [(x, ()) | x <- xs])
    dominates (s', t', h') (s, t, h) = h' == h && s' >= s && t' >= t && (s', t') /= (s, t)

-- | The ways to take one partial or complete group off the lowest number, or to
-- give up on that number (its remaining tiles stay isolated).
moves :: Bool -> [Int] -> [(Partial, [Int])]
moves _ [] = []
moves honor (c : xs) = concat
  [ [((1, 0, 0), c - 3 : xs) | c >= 3]
  , [((1, 0, 0), c - 1 : b - 1 : d - 1 : ys) | not honor, b : d : ys <- [xs], b > 0, d > 0]
  , [((0, 0, 1), c - 2 : xs) | c >= 2]
  , [((0, 1, 0), c - 2 : xs) | c >= 2]
  , [((0, 1, 0), c - 1 : b - 1 : ys) | not honor, b : ys <- [xs], b > 0]
  , [((0, 1, 0), c - 1 : b : d - 1 : ys) | not honor, b : d : ys <- [xs], d > 0]
  , [((0, 0, 0), xs)]
  ]

-- | Every (Pareto-best) outcome for one suit; memoised on the remaining counts.
suitPartials :: Bool -> [Int] -> [Partial]
suitPartials honor counts = evalState (go counts) M.empty
  where
    go [] = pure [(0, 0, 0)]
    go (0 : xs) = go xs
    go cs = gets (M.lookup cs) >>= \case
      Just r -> pure r
      Nothing -> do
        r <- prune . concat <$> mapM step (moves honor cs)
        modify (M.insert cs r)
        pure r
    step (d, rest) = do
      ps <- go rest
      pure [add d p | p <- ps, pairOf d + pairOf p <= 1]
    pairOf (_, _, h) = h
    add (a, b, c) (x, y, z) = (a + x, b + y, c + z)

-- | Standard-form shanten: 8 − 2·sets − partials − pair, sets + partials ≤ 4,
-- with the declared melds counted as sets.
shantenStd :: Int -> [Kind] -> Int
shantenStd melds = fromTables melds . suitTables

-- | Outcomes per suit, in suit order.
suitTables :: [Kind] -> [[Partial]]
suitTables ks = [suitTable s (suitCounts m s) | s <- [minBound .. maxBound]]
  where m = tally ks

suitTable :: Suit -> [Int] -> [Partial]
suitTable s = suitPartials (s == Honor)

fromTables :: Int -> [[Partial]] -> Int
fromTables melds tables = 8 - maximum (map value (foldl' combine [(melds, 0, 0)] tables))
  where
    combine as bs = prune [(s1 + s2, t1 + t2, h1 + h2) | (s1, t1, h1) <- as, (s2, t2, h2) <- bs, h1 + h2 <= 1]
    value (s, t, h) = 2 * s + min t (4 - s) + h

shantenChiitoi :: [Kind] -> Int
shantenChiitoi ks = 6 - pairs + max 0 (7 - kinds)
  where
    cs = M.elems (tally ks)
    pairs = length (filter (>= 2) cs)
    kinds = length cs

shantenKokushi :: [Kind] -> Int
shantenKokushi ks = 13 - M.size y - (if any (>= 2) (M.elems y) then 1 else 0)
  where y = tally (filter isYaochu ks)

-- | The lowest of the three; chiitoi and kokushi only without melds.
shantenMin :: Int -> [Kind] -> Int
shantenMin 0 ks = minimum [shantenStd 0 ks, shantenChiitoi ks, shantenKokushi ks]
shantenMin melds ks = shantenStd melds ks

-- | Kinds whose draw lowers 'shantenMin', ignoring availability (structural waits
-- when the hand is tenpai).
improving :: Int -> [Kind] -> [Kind]
improving melds ks = [k | k <- allKinds, after k < now]
  where
    now = shantenMin melds ks
    m = tally ks
    tables = suitTables ks
    -- Drawing k only changes k's suit, so only that suit is searched again.
    after k =
      let s = suit k
          table' = suitTable s (suitCounts (M.insertWith (+) k 1 m) s)
          std = fromTables melds [if s' == s then table' else t | (s', t) <- zip [minBound ..] tables]
       in if melds == 0 then minimum [std, shantenChiitoi (k : ks), shantenKokushi (k : ks)] else std

-- | The @waits@ op: shanten, the improving kinds with a copy left outside the
-- given tiles (hand and melds), and how many copies that is.
liveWaits :: Int -> [Kind] -> [Kind] -> (Int, [Kind], Int)
liveWaits melds concealed seen = (shantenMin melds concealed, live, sum (map left live))
  where
    left k = 4 - countOf k seen
    live = [k | k <- improving melds concealed, left k > 0]
