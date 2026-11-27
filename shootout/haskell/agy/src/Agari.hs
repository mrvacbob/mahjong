module Agari
  ( GroupKind (..)
  , CGroup (..)
  , Decomp (..)
  , decompose
  , formatDecomps
  , isAgari
  , isKokushi
  , isChiitoi
  , structuralWaits
  ) where

import Data.Array.Unboxed ((!), (//))
import Data.List (intercalate, nub, sort)
import Tile

data GroupKind = Pair | Seq | Triplet | Kan
  deriving (Eq, Ord, Show)

-- | Concealed group. Derived Ord matches the spec's agari group ordering:
-- suit (m, p, s, z), then first digit, then Pair < Seq < Triplet.
data CGroup = CGroup !TileKind !GroupKind
  deriving (Eq, Ord, Show)

data Decomp
  = StdDecomp !TileKind ![CGroup]   -- pair kind + concealed sets (Seq/Triplet)
  | ChiitoiDecomp ![TileKind]       -- 7 distinct pair kinds
  | KokushiDecomp
  deriving (Eq, Show)

isChiitoi :: Counts -> Bool
isChiitoi c = go 0 0 0
  where
    go :: Int -> Int -> Int -> Bool
    go 34 pairs total = pairs == 7 && total == 14
    go i  pairs total =
      let n = c ! i
      in if n == 0 then go (i + 1) pairs total
         else if n == 2 then go (i + 1) (pairs + 1) (total + 2)
         else False

isKokushi :: Counts -> Bool
isKokushi c =
  let ys = [countsAt c k | k <- yaochuKinds]
  in countsTotal c == 14 && sum ys == 14 && all (>= 1) ys

-- | Decompose concealed tiles (14 - 3*nMelds) into all valid complete forms.
decompose :: Counts -> Int -> [Decomp]
decompose c nMelds = stds ++ chiitois ++ kokushis
  where
    needSets = 4 - nMelds
    stds =
      [ StdDecomp (TileKind p) sets
      | p <- [0 .. 33]
      , c ! p >= 2
      , let c' = c // [(p, c ! p - 2)]
      , sets <- decomposeSets c' needSets 0 False
      ]
    chiitois
      | nMelds == 0 && isChiitoi c =
          [ChiitoiDecomp [TileKind i | i <- [0 .. 33], c ! i == 2]]
      | otherwise = []
    kokushis
      | nMelds == 0 && isKokushi c = [KokushiDecomp]
      | otherwise = []

-- | Decompose remaining tiles into exactly `need` sets without duplicate multisets.
-- `startIdx` is the lowest index to inspect; `triOnly` forbids taking Seq at `startIdx`
-- once a Triplet has been taken at `startIdx` (since Seq < Triplet).
decomposeSets :: Counts -> Int -> Int -> Bool -> [[CGroup]]
decomposeSets _ 0 _ _ = [[]]
decomposeSets c need startIdx triOnly =
  case findFirst startIdx of
    Nothing -> []
    Just i  ->
      let triOnlyHere = triOnly && i == startIdx
          seqRes
            | not triOnlyHere && i < 27 && (i `mod` 9) <= 6
                && c ! (i + 1) >= 1 && c ! (i + 2) >= 1 =
                let c' = c // [(i, c ! i - 1), (i + 1, c ! (i + 1) - 1), (i + 2, c ! (i + 2) - 1)]
                in map (CGroup (TileKind i) Seq :) (decomposeSets c' (need - 1) i False)
            | otherwise = []
          triRes
            | c ! i >= 3 =
                let c' = c // [(i, c ! i - 3)]
                in map (CGroup (TileKind i) Triplet :) (decomposeSets c' (need - 1) i True)
            | otherwise = []
      in seqRes ++ triRes
  where
    findFirst idx
      | idx >= 34  = Nothing
      | c ! idx > 0 = Just idx
      | otherwise  = findFirst (idx + 1)

formatCGroup :: CGroup -> String
formatCGroup (CGroup k gk) =
  let r = kindRank k
      s = suitChar (kindSuit k)
      d n = toEnum (fromEnum '0' + n)
  in case gk of
    Pair    -> [d r, d r, s]
    Seq     -> [d r, d (r + 1), d (r + 2), s]
    Triplet -> [d r, d r, d r, s]
    Kan     -> [d r, d r, d r, d r, s]

formatDecomp :: Decomp -> String
formatDecomp KokushiDecomp   = "kokushi"
formatDecomp (ChiitoiDecomp _) = "chiitoi"
formatDecomp (StdDecomp p sets) =
  intercalate "," (map formatCGroup (sort (CGroup p Pair : sets)))

formatDecomps :: [Decomp] -> [String]
formatDecomps = nub . sort . map formatDecomp

isAgari :: Counts -> Int -> Bool
isAgari c nMelds = not (null (decompose c nMelds))

-- | Structural wait kinds for a 13-3k hand (ignoring 4-copy tile limits).
structuralWaits :: Counts -> Int -> [TileKind]
structuralWaits c nMelds =
  [ k | k <- allKinds, isAgari (countsAdd k 1 c) nMelds ]
