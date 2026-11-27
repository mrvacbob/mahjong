-- | Tiles in mpsz notation.
--
-- 'Kind' is what the rules reason about; 'Tile' adds the red-five bit that the
-- protocol keeps distinct (aka dora, @discard:0m@ vs @discard:5m@).
module Tile
  ( Suit (..), Kind (..), Tile (..)
  , numberSuits, allKinds, kindsOf
  , isHonor, isTerminal, isYaochu, isSimple, isDragon, isWind, isGreen
  , next, doraOf
  , parseTile, parseTiles, parseKind
  , showTile, showTiles, showKind, showKinds
  ) where

import Data.Char (isDigit, digitToInt, intToDigit)
import Data.List (groupBy, sort)
import Data.Function (on)

data Suit = Man | Pin | Sou | Honor
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | A tile kind: suit and number (1..9 for suits, 1..7 for honors:
-- E S W N haku hatsu chun).
data Kind = Kind { suit :: !Suit, num :: !Int }
  deriving (Eq, Ord, Show)

data Tile = Tile { kind :: !Kind, red :: !Bool }
  deriving (Eq, Show)

-- | Canonical order: by kind, and a red five just before the plain five.
instance Ord Tile where
  compare = compare `on` \t -> (kind t, not (red t))

numberSuits :: [Suit]
numberSuits = [Man, Pin, Sou]

allKinds :: [Kind]
allKinds = [Kind s n | s <- numberSuits, n <- [1 .. 9]] ++ [Kind Honor n | n <- [1 .. 7]]

kindsOf :: [Tile] -> [Kind]
kindsOf = map kind

isHonor, isTerminal, isYaochu, isSimple, isDragon, isWind, isGreen :: Kind -> Bool
isHonor = (== Honor) . suit
isTerminal k = not (isHonor k) && (num k == 1 || num k == 9)
isYaochu k = isHonor k || isTerminal k
isSimple = not . isYaochu
isDragon k = isHonor k && num k >= 5
isWind k = isHonor k && num k <= 4
isGreen k = k `elem` [Kind Sou 2, Kind Sou 3, Kind Sou 4, Kind Sou 6, Kind Sou 8, Kind Honor 6]

-- | The kind after this one, wrapping within its group (9→1, N→E, chun→haku).
next :: Kind -> Kind
next (Kind Honor n)
  | n == 4 = Kind Honor 1
  | n == 7 = Kind Honor 5
  | otherwise = Kind Honor (n + 1)
next (Kind s n) = Kind s (if n == 9 then 1 else n + 1)

-- | The dora indicated by an indicator tile.
doraOf :: Tile -> Kind
doraOf = next . kind

suitChar :: Suit -> Char
suitChar s = case s of Man -> 'm'; Pin -> 'p'; Sou -> 's'; Honor -> 'z'

charSuit :: Char -> Maybe Suit
charSuit c = lookup c [('m', Man), ('p', Pin), ('s', Sou), ('z', Honor)]

mkTile :: Suit -> Int -> Maybe Tile
mkTile Honor d | d >= 1 && d <= 7 = Just (Tile (Kind Honor d) False)
mkTile Honor _ = Nothing
mkTile s 0 = Just (Tile (Kind s 5) True)
mkTile s d = Just (Tile (Kind s d) False)

-- | A tile list such as @123m406p77z@, or @-@ for none.
parseTiles :: String -> Maybe [Tile]
parseTiles "-" = Just []
parseTiles str = go [] str
  where
    go [] [] = Just []
    go _ [] = Nothing                       -- digits without a suit letter
    go ds (c : cs)
      | isDigit c = go (ds ++ [digitToInt c]) cs
      | Just s <- charSuit c, not (null ds) = (++) <$> traverse (mkTile s) ds <*> go [] cs
      | otherwise = Nothing

parseTile :: String -> Maybe Tile
parseTile str = case parseTiles str of
  Just [t] -> Just t
  _ -> Nothing

parseKind :: String -> Maybe Kind
parseKind = fmap kind . parseTile

digitOf :: Tile -> Char
digitOf t = if red t then '0' else intToDigit (num (kind t))

-- | Print tiles in canonical order, grouped by suit.
showTiles :: [Tile] -> String
showTiles [] = "-"
showTiles ts = concatMap group (groupBy ((==) `on` (suit . kind)) (sort ts))
  where
    group g@(t : _) = map digitOf g ++ [suitChar (suit (kind t))]
    group [] = ""

showTile :: Tile -> String
showTile t = showTiles [t]

plain :: Kind -> Tile
plain k = Tile k False

showKinds :: [Kind] -> String
showKinds = showTiles . map plain

showKind :: Kind -> String
showKind = showKinds . pure
