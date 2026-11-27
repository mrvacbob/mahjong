-- | Melds and the unified 'Group' that scoring works on.
module Meld
  ( Form (..), Group (..), groupKinds, isSetLike
  , MeldType (..), Meld (..), meldGroup, meldKinds, isOpenMeld, closedHand
  , parseMeld, parseMelds, showGroup, splitOn
  ) where

import Tile
import Control.Monad (guard)
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
  Run -> [k, offset 1 k, offset 2 k]
  Triplet -> [k, k, k]
  Quad -> [k, k, k, k]

-- | Triplet or quad: what toitoi, sanankou and yakuhai count.
isSetLike :: Group -> Bool
isSetLike g = gform g == Triplet || gform g == Quad

data MeldType = Chi | Pon | Daiminkan | Shouminkan | Ankan
  deriving (Eq, Show)

data Meld = Meld { mtype :: !MeldType, mtiles :: [Tile] }
  deriving (Eq, Show)

-- | Does this meld open the hand? (A closed kan does not.)
isOpenMeld :: Meld -> Bool
isOpenMeld m = mtype m /= Ankan

closedHand :: [Meld] -> Bool
closedHand = not . any isOpenMeld

meldGroup :: Meld -> Group
meldGroup m = Group form (minimum (map kind (mtiles m))) (isOpenMeld m)
  where
    form = case mtype m of
      Chi -> Run
      Pon -> Triplet
      _ -> Quad

meldKinds :: [Meld] -> [Kind]
meldKinds = concatMap (map kind . mtiles)

-- | @c345m@, @p777z@, @k1111p@, @s0555s@, @a2222m@: the tiles must be exactly
-- the group the meld type names.
parseMeld :: String -> Maybe Meld
parseMeld [] = Nothing
parseMeld (c : rest) = do
  t <- lookup c [('c', Chi), ('p', Pon), ('k', Daiminkan), ('s', Shouminkan), ('a', Ankan)]
  ts@(_ : _) <- parseTiles rest
  let m = Meld t ts
      g = meldGroup m
  guard (not (gform g == Run && isHonor (gbase g)) && sort (map kind ts) == groupKinds g)
  pure m

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
