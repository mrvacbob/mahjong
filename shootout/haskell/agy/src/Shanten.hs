module Shanten
  ( ShantenResult (..)
  , WaitsResult (..)
  , computeShanten
  , computeWaits
  ) where

import Control.Monad (forM_, when)
import Control.Monad.ST (ST, runST)
import Data.Array.ST (STUArray, newArray, readArray, writeArray)
import Data.Array.Unboxed ((!))
import Tile

data ShantenResult = ShantenResult
  { shStd     :: !Int
  , shChiitoi :: !(Maybe Int)
  , shKokushi :: !(Maybe Int)
  , shMin     :: !Int
  } deriving (Eq, Show)

data WaitsResult = WaitsResult
  { wrShanten :: !Int
  , wrTiles   :: ![TileKind]
  , wrCount   :: !Int
  } deriving (Eq, Show)

-- | 5-element table mapping number of sets (0..4) to max taatsu (-1 if unreachable).
data SuitProfile = SuitProfile
  { spNoHead   :: !(Int, Int, Int, Int, Int)
  , spWithHead :: !(Int, Int, Int, Int, Int)
  } deriving (Eq, Show)

type Vec5 = (Int, Int, Int, Int, Int)

emptyVec5 :: Vec5
emptyVec5 = (-1, -1, -1, -1, -1)

-- | Combine two Vec5 tables (additive sets and taatsu, capped at 4 sets).
combineVec5 :: Vec5 -> Vec5 -> Vec5
combineVec5 (a0, a1, a2, a3, a4) (b0, b1, b2, b3, b4) =
  ( m0, m1, m2, m3, m4 )
  where
    addV x y = if x < 0 || y < 0 then -1 else x + y
    m0 = addV a0 b0
    m1 = max (addV a0 b1) (addV a1 b0)
    m2 = max (addV a0 b2) (max (addV a1 b1) (addV a2 b0))
    m3 = max (addV a0 b3) (max (addV a1 b2) (max (addV a2 b1) (addV a3 b0)))
    m4 = max (addV a0 b4) (max (addV a1 b3) (max (addV a2 b2) (max (addV a3 b1) (addV a4 b0))))

maxVec5 :: Vec5 -> Vec5 -> Vec5
maxVec5 (a0, a1, a2, a3, a4) (b0, b1, b2, b3, b4) =
  (max a0 b0, max a1 b1, max a2 b2, max a3 b3, max a4 b4)

combineProfile :: SuitProfile -> SuitProfile -> SuitProfile
combineProfile (SuitProfile n1 h1) (SuitProfile n2 h2) =
  SuitProfile
    (combineVec5 n1 n2)
    (maxVec5 (combineVec5 h1 n2) (combineVec5 n1 h2))

-- | Compute SuitProfile for a numbered suit starting at base index (0, 9, or 18).
numberedSuitProfile :: Counts -> Int -> SuitProfile
numberedSuitProfile c base = runST $ do
  arr <- newArray (0, 8) 0 :: ST s (STUArray s Int Int)
  forM_ [0 .. 8] $ \i -> writeArray arr i (c ! (base + i))
  noH <- searchSuit arr
  bestH <- newArray (0, 4) (-1) :: ST s (STUArray s Int Int)
  forM_ [0 .. 8] $ \r -> do
    v <- readArray arr r
    when (v >= 2) $ do
      writeArray arr r (v - 2)
      dfsSuit arr bestH 0 0 0 0
      writeArray arr r v
  withH <- readVec5 bestH
  pure (SuitProfile noH withH)

searchSuit :: STUArray s Int Int -> ST s Vec5
searchSuit arr = do
  best <- newArray (0, 4) (-1) :: ST s (STUArray s Int Int)
  dfsSuit arr best 0 0 0 0
  readVec5 best

readVec5 :: STUArray s Int Int -> ST s Vec5
readVec5 best = do
  v0 <- readArray best 0
  v1 <- readArray best 1
  v2 <- readArray best 2
  v3 <- readArray best 3
  v4 <- readArray best 4
  pure (v0, v1, v2, v3, v4)

-- | DFS over ranks 0..8 extracting sets and taatsu.
-- `minOp` prevents duplicate permutations at the same rank `i`:
-- 0 = triplet, 1 = sequence, 2 = pair-taatsu, 3 = i/i+1, 4 = i/i+2.
dfsSuit :: STUArray s Int Int -> STUArray s Int Int -> Int -> Int -> Int -> Int -> ST s ()
dfsSuit arr best i sets taatsu minOp
  | sets > 4 = pure ()
  | i == 9 = do
      cur <- readArray best sets
      when (taatsu > cur) $ writeArray best sets taatsu
  | otherwise = do
      ci <- readArray arr i
      if ci == 0
        then dfsSuit arr best (i + 1) sets taatsu 0
        else do
          -- 0: Triplet
          when (minOp <= 0 && ci >= 3) $ do
            writeArray arr i (ci - 3)
            dfsSuit arr best i (sets + 1) taatsu 0
            writeArray arr i ci
          -- 1: Sequence (i, i+1, i+2)
          when (minOp <= 1 && i <= 6) $ do
            c1 <- readArray arr (i + 1)
            c2 <- readArray arr (i + 2)
            when (c1 >= 1 && c2 >= 1) $ do
              writeArray arr i (ci - 1)
              writeArray arr (i + 1) (c1 - 1)
              writeArray arr (i + 2) (c2 - 1)
              dfsSuit arr best i (sets + 1) taatsu 1
              writeArray arr i ci
              writeArray arr (i + 1) c1
              writeArray arr (i + 2) c2
          -- 2: Pair taatsu
          when (minOp <= 2 && ci >= 2) $ do
            writeArray arr i (ci - 2)
            dfsSuit arr best i sets (taatsu + 1) 2
            writeArray arr i ci
          -- 3: Adjacent taatsu (i, i+1)
          when (minOp <= 3 && i <= 7) $ do
            c1 <- readArray arr (i + 1)
            when (c1 >= 1) $ do
              writeArray arr i (ci - 1)
              writeArray arr (i + 1) (c1 - 1)
              dfsSuit arr best i sets (taatsu + 1) 3
              writeArray arr i ci
              writeArray arr (i + 1) c1
          -- 4: Kanchan taatsu (i, i+2)
          when (minOp <= 4 && i <= 6) $ do
            c2 <- readArray arr (i + 2)
            when (c2 >= 1) $ do
              writeArray arr i (ci - 1)
              writeArray arr (i + 2) (c2 - 1)
              dfsSuit arr best i sets (taatsu + 1) 4
              writeArray arr i ci
              writeArray arr (i + 2) c2
          -- Skip remaining copies of rank i
          dfsSuit arr best (i + 1) sets taatsu 0

-- | Compute SuitProfile for honors (indices 27..33).
honorSuitProfile :: Counts -> SuitProfile
honorSuitProfile c = SuitProfile noH withH
  where
    hs = [c ! i | i <- [27 .. 33]]
    evalNoHead xs =
      let s = length [x | x <- xs, x >= 3]
          t = length [x | x <- xs, x == 2]
      in setVec5 s t emptyVec5
    noH = evalNoHead hs
    withH = foldl maxVec5 emptyVec5
      [ evalNoHead (take idx hs ++ [x - 2] ++ drop (idx + 1) hs)
      | (idx, x) <- zip [0 ..] hs
      , x >= 2
      ]

setVec5 :: Int -> Int -> Vec5 -> Vec5
setVec5 0 t (_, a1, a2, a3, a4) = (t, a1, a2, a3, a4)
setVec5 1 t (a0, _, a2, a3, a4) = (a0, t, a2, a3, a4)
setVec5 2 t (a0, a1, _, a3, a4) = (a0, a1, t, a3, a4)
setVec5 3 t (a0, a1, a2, _, a4) = (a0, a1, a2, t, a4)
setVec5 4 t (a0, a1, a2, a3, _) = (a0, a1, a2, a3, t)
setVec5 _ _ v                   = v

stdShantenFromProfile :: Int -> SuitProfile -> Int
stdShantenFromProfile nMelds (SuitProfile noH withH) =
  min (evalVec 0 noH) (evalVec 1 withH)
  where
    evalVec h (t0, t1, t2, t3, t4) =
      minimum
        ( 99
        : [ score s t
          | (s, t) <- [(0, t0), (1, t1), (2, t2), (3, t3), (4, t4)]
          , t >= 0
          ]
        )
      where
        score s t =
          let totS = min 4 (s + nMelds)
              totT = min (4 - totS) t
          in 8 - 2 * totS - totT - h

chiitoiShanten :: Counts -> Int
chiitoiShanten c = 6 - pairs + max 0 (7 - kinds)
  where
    (pairs, kinds) = go 0 0 0
    go 34 p k = (p, k)
    go i  p k =
      let n = c ! i
      in go (i + 1) (if n >= 2 then p + 1 else p) (if n >= 1 then k + 1 else k)

kokushiShanten :: Counts -> Int
kokushiShanten c = 13 - kinds - (if hasPair then 1 else 0)
  where
    ks = [countsAt c k | k <- yaochuKinds]
    kinds = length [x | x <- ks, x >= 1]
    hasPair = any (>= 2) ks

computeShanten :: Counts -> Int -> ShantenResult
computeShanten c nMelds =
  let pm = numberedSuitProfile c 0
      pp = numberedSuitProfile c 9
      ps = numberedSuitProfile c 18
      pz = honorSuitProfile c
      comb = combineProfile (combineProfile pm pp) (combineProfile ps pz)
      std = stdShantenFromProfile nMelds comb
  in if nMelds > 0
       then ShantenResult std Nothing Nothing std
       else
         let ch = chiitoiShanten c
             ko = kokushiShanten c
         in ShantenResult std (Just ch) (Just ko) (min std (min ch ko))

-- | Compute tile kinds that lower min shanten when drawn, filtered by live copies (< 4 used).
computeWaits :: [Tile] -> [Meld] -> WaitsResult
computeWaits hand melds =
  let c = countsFromTiles hand
      used = allHandMeldsCounts hand melds
      nMelds = length melds
      pm = numberedSuitProfile c 0
      pp = numberedSuitProfile c 9
      ps = numberedSuitProfile c 18
      pz = honorSuitProfile c
      combBase = combineProfile (combineProfile pm pp) (combineProfile ps pz)
      baseStd = stdShantenFromProfile nMelds combBase
      baseMin =
        if nMelds > 0
          then baseStd
          else min baseStd (min (chiitoiShanten c) (kokushiShanten c))
      -- Pre-combine triples of suits so each candidate tile only recomputes its own suit
      pNotM = combineProfile (combineProfile pp ps) pz
      pNotP = combineProfile (combineProfile pm ps) pz
      pNotS = combineProfile (combineProfile pm pp) pz
      pNotZ = combineProfile (combineProfile pm pp) ps

      improves k@(TileKind idx) =
        let c' = countsAdd k 1 c
            prof' = case kindSuit k of
              Man   -> combineProfile (numberedSuitProfile c' 0)  pNotM
              Pin   -> combineProfile (numberedSuitProfile c' 9)  pNotP
              Sou   -> combineProfile (numberedSuitProfile c' 18) pNotS
              Honor -> combineProfile (honorSuitProfile c')       pNotZ
            std' = stdShantenFromProfile nMelds prof'
            min' =
              if nMelds > 0
                then std'
                else min std' (min (chiitoiShanten c') (kokushiShanten c'))
        in min' < baseMin && (used ! idx) < 4

      ws = [k | k <- allKinds, improves k]
      cnt = sum [4 - (used ! unKind k) | k <- ws]
  in WaitsResult baseMin ws cnt
