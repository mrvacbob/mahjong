module Tiles where

import Control.Monad (guard)
import Data.Char (digitToInt, intToDigit)
import Data.List (elemIndex, groupBy, intercalate, sortOn)

type Kind = Int

data Tile = Tile { kind :: !Kind, red :: !Bool } deriving (Eq, Ord)
data Call = Chi | Pon | OpenKan | AddedKan | ClosedKan deriving (Eq)
data Meld = Meld { call :: Call, meldTiles :: [Tile] }

data Context = Context
    { seat :: Kind
    , roundWind :: Kind
    , indicators :: [Tile]
    , uraIndicators :: [Tile]
    , honba :: Int
    , flags :: [String]
    }

kinds :: [Kind]
kinds = [0..33]

suit :: Kind -> Int
suit k = k `div` 9

rank :: Kind -> Int
rank k = k `mod` 9 + 1

honor, terminal, outside :: Kind -> Bool
honor k = k >= 27
terminal k = not (honor k) && rank k `elem` [1,9]
outside k = honor k || terminal k

suitedNeighbors :: Kind -> [Kind]
suitedNeighbors k
    | honor k = []
    | otherwise = [n | n <- [k-2..k+2], n >= 0, n /= k, suit n == suit k]

sequenceStarts :: Kind -> [Kind]
sequenceStarts k =
    [n | n <- [k-2..k], n >= 0, not (honor k), suit n == suit k, rank n <= 7]

plain :: Kind -> Tile
plain k = Tile k False

parseTile :: String -> Maybe Tile
parseTile [digit, letter] = do
    s <- elemIndex letter "mpsz"
    guard (digit `elem` "0123456789")
    let r = digitToInt digit
    guard (if s == 3 then r >= 1 && r <= 7 else True)
    pure (Tile (9*s + (if r == 0 then 5 else r) - 1) (r == 0))
parseTile _ = Nothing

parseTiles :: String -> Maybe [Tile]
parseTiles "-" = Just []
parseTiles [] = Just []
parseTiles str = case span (`elem` "0123456789") str of
    (digits, letter:rest) | not (null digits) ->
        (++) <$> traverse (\d -> parseTile [d, letter]) digits <*> parseTiles rest
    _ -> Nothing

split :: Char -> String -> [String]
split delimiter str = case break (== delimiter) str of
    (word, []) -> [word]
    (word, _:rest) -> word : split delimiter rest

parseMeld :: String -> Maybe Meld
parseMeld (tag:tiles) = do
    c <- lookup tag [('c',Chi),('p',Pon),('k',OpenKan),('s',AddedKan),('a',ClosedKan)]
    ts <- parseTiles tiles
    case map kind ts of
        a:rest -> guard $ case c of
            Chi -> rank a <= 7 && not (honor a) && rest == [a+1,a+2]
            Pon -> rest == replicate 2 a
            _ -> rest == replicate 3 a
        [] -> Nothing
    pure (Meld c ts)
parseMeld _ = Nothing

parseMelds :: String -> Maybe [Meld]
parseMelds "-" = Just []
parseMelds str = traverse parseMeld (split ',' str)

isClosed :: [Meld] -> Bool
isClosed = all ((== ClosedKan) . call)

isKan :: Meld -> Bool
isKan m = call m `elem` [OpenKan, AddedKan, ClosedKan]

tileDigit :: Tile -> Char
tileDigit t
    | red t = '0'
    | otherwise = intToDigit (rank (kind t))

tileSuit :: Tile -> Char
tileSuit t = "mpsz" !! suit (kind t)

showTile :: Tile -> String
showTile t = [tileDigit t, tileSuit t]

showTiles :: [Tile] -> String
showTiles [] = "-"
showTiles ts = concatMap render bySuit
  where
    bySuit = groupBy (\a b -> tileSuit a == tileSuit b) (sortOn (\t -> (kind t, not (red t))) ts)
    render [] = ""
    render group@(t:_) = map tileDigit group ++ [tileSuit t]

join :: Char -> [String] -> String
join c = intercalate [c]

doraKind :: Kind -> Kind
doraKind k
    | k < 27 = suit k * 9 + rank k `mod` 9
    | k < 31 = 27 + (k - 26) `mod` 4
    | otherwise = 31 + (k - 30) `mod` 3
