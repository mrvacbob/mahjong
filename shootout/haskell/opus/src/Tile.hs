-- | Tiles in mpsz notation.
--
-- 'Kind' is what the rules reason about; 'Tile' adds the red-five bit that the
-- protocol keeps distinct (aka dora, @discard:0m@ vs @discard:5m@).
module Tile
  ( Suit (..), Kind (..), Tile (..)
  , numberSuits, numbers, allKinds, offset, east, winds, dragons
  , isHonor, isTerminal, isYaochu, isSimple, isDragon, isWind, isGreen
  , next, doraOf, count, countOf
  , parseTile, parseTiles
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

numbers :: Suit -> [Int]
numbers Honor = [1 .. 7]
numbers _ = [1 .. 9]

allKinds :: [Kind]
allKinds = [Kind s n | s <- [minBound .. maxBound], n <- numbers s]

-- | The kind @d@ numbers further along the same suit (may leave 1..9).
offset :: Int -> Kind -> Kind
offset d k = k { num = num k + d }

east :: Kind
east = Kind Honor 1

winds, dragons :: [Kind]
winds = [Kind Honor n | n <- [1 .. 4]]
dragons = [Kind Honor n | n <- [5 .. 7]]

isHonor, isTerminal, isYaochu, isSimple, isDragon, isWind, isGreen :: Kind -> Bool
isHonor = (== Honor) . suit
isTerminal k = not (isHonor k) && (num k == 1 || num k == 9)
isYaochu k = isHonor k || isTerminal k
isSimple = not . isYaochu
isDragon = (`elem` dragons)
isWind = (`elem` winds)
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

count :: (a -> Bool) -> [a] -> Int
count p = length . filter p

countOf :: Eq a => a -> [a] -> Int
countOf x = count (== x)

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
parseTiles str = go str
  where
    go [] = Just []
    go cs = case span isDigit cs of
      (ds@(_ : _), c : rest) | Just s <- charSuit c ->
        (++) <$> traverse (mkTile s . digitToInt) ds <*> go rest
      _ -> Nothing                          -- no digits, or digits without a suit

parseTile :: String -> Maybe Tile
parseTile str = case parseTiles str of
  Just [t] -> Just t
  _ -> Nothing

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

showKinds :: [Kind] -> String
showKinds = showTiles . map (`Tile` False)

showKind :: Kind -> String
showKind = showKinds . pure
