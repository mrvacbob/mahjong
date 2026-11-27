-- | Melds and the unified 'Group' that scoring works on.
module Meld
  ( Form (..), Group (..), groupKinds, isSetLike
  , MeldType (..), Meld (..), meldGroup, isKan, isOpenMeld
  , parseMeld, parseMelds, showGroup
  ) where

import Tile
import Data.List (sort)

-- | Constructor order is the order groups print in within one starting tile:
-- pair < run < triplet.
data Form = Pair | Run | Triplet | Quad
  deriving (Eq, Ord, Show)

-- | A group of a complete hand: concealed groups from the decomposition and the
-- declared melds alike. 'gopen' is what fu and "concealed triplet" yaku read;
-- a shanpon triplet completed by ron is a hand group with @gopen = True@.
data Group = Group { gform :: !Form, gbase :: !Kind, gopen :: !Bool }
  deriving (Eq, Ord, Show)

groupKinds :: Group -> [Kind]
groupKinds (Group f k _) = case f of
  Pair -> [k, k]
  Run -> [k, k { num = num k + 1 }, k { num = num k + 2 }]
  Triplet -> [k, k, k]
  Quad -> [k, k, k, k]

-- | Triplet or quad: what toitoi, sanankou and yakuhai count.
isSetLike :: Group -> Bool
isSetLike g = gform g == Triplet || gform g == Quad

data MeldType = Chi | Pon | Daiminkan | Shouminkan | Ankan
  deriving (Eq, Show)

data Meld = Meld { mtype :: !MeldType, mtiles :: [Tile] }
  deriving (Eq, Show)

isKan :: Meld -> Bool
isKan m = mtype m `elem` [Daiminkan, Shouminkan, Ankan]

-- | Does this meld open the hand? (A closed kan does not.)
isOpenMeld :: Meld -> Bool
isOpenMeld m = mtype m /= Ankan

meldGroup :: Meld -> Group
meldGroup (Meld t ts) = Group form (minimum (map kind ts)) (t /= Ankan)
  where
    form = case t of
      Chi -> Run
      Pon -> Triplet
      _ -> Quad

-- | @c345m@, @p777z@, @k1111p@, @s0555s@, @a2222m@.
parseMeld :: String -> Maybe Meld
parseMeld [] = Nothing
parseMeld (c : rest) = do
  t <- lookup c [('c', Chi), ('p', Pon), ('k', Daiminkan), ('s', Shouminkan), ('a', Ankan)]
  ts <- parseTiles rest
  ks@(k0 : _) <- Just (sort (map kind ts))
  let isRun = not (isHonor k0) && ks == [k0, k0 { num = num k0 + 1 }, k0 { num = num k0 + 2 }]
      isSame n = length ks == n && all (== k0) ks
      ok = case t of
        Chi -> isRun
        Pon -> isSame 3
        _ -> isSame 4
  if ok then Just (Meld t ts) else Nothing

parseMelds :: String -> Maybe [Meld]
parseMelds "-" = Just []
parseMelds s = traverse parseMeld (splitOn ',' s)

splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, []) -> [a]
  (a, _ : b) -> a : splitOn c b

-- | Print a concealed group as a tile list, reds as 5.
showGroup :: Group -> String
showGroup = showKinds . groupKinds
