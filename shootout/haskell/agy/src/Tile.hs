module Tile
  ( Suit (..)
  , Wind (..)
  , TileKind (..)
  , Tile (..)
  , MeldKind (..)
  , Meld (..)
  , Counts
  , allKinds
  , yaochuKinds
  , mkKind
  , kindSuit
  , kindRank
  , windKind
  , parseWind
  , isSuit
  , isHonor
  , isTerminal
  , isSimple
  , isYaochu
  , isWind
  , isDragon
  , isGreen
  , doraNext
  , suitChar
  , formatKind
  , formatKinds
  , formatTile
  , formatTiles
  , parseTile
  , parseTiles
  , isOpenMeld
  , isKanMeld
  , parseMeld
  , parseMelds
  , countsEmpty
  , countsFromKinds
  , countsFromTiles
  , countsAdd
  , countsTotal
  , countsAt
  , allHandMeldsCounts
  ) where

import Data.Array.Unboxed (UArray, accumArray, (!), (//))
import Data.Char (digitToInt, isDigit)
import Data.Ix (Ix)
import Data.List (groupBy, sort)

data Suit = Man | Pin | Sou | Honor
  deriving (Eq, Ord, Enum, Bounded, Show)

data Wind = East | South | West | North
  deriving (Eq, Ord, Enum, Bounded, Show)

-- | Tile kind 0..33:
-- 0..8   = 1m..9m
-- 9..17  = 1p..9p
-- 18..26 = 1s..9s
-- 27..30 = 1z..4z (East, South, West, North)
-- 31..33 = 5z..7z (Haku, Hatsu, Chun)
newtype TileKind = TileKind { unKind :: Int }
  deriving (Eq, Ord, Ix, Show)

data Tile = Tile
  { tileKind :: !TileKind
  , tileRed  :: !Bool
  } deriving (Eq, Show)

-- Canonical order: by kind ascending, with red five (0) immediately before plain five (5).
instance Ord Tile where
  compare (Tile k1 r1) (Tile k2 r2) =
    compare k1 k2 <> compare (not r1) (not r2)

data MeldKind = Chi | Pon | Daiminkan | Shouminkan | Ankan
  deriving (Eq, Ord, Show)

data Meld = Meld
  { meldKind  :: !MeldKind
  , meldTiles :: ![Tile]
  } deriving (Eq, Show)

type Counts = UArray Int Int

allKinds :: [TileKind]
allKinds = map TileKind [0 .. 33]

yaochuKinds :: [TileKind]
yaochuKinds = map TileKind [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]

mkKind :: Suit -> Int -> TileKind
mkKind Man   r = TileKind (r - 1)
mkKind Pin   r = TileKind (9 + r - 1)
mkKind Sou   r = TileKind (18 + r - 1)
mkKind Honor r = TileKind (27 + r - 1)

kindSuit :: TileKind -> Suit
kindSuit (TileKind k)
  | k < 9     = Man
  | k < 18    = Pin
  | k < 27    = Sou
  | otherwise = Honor

kindRank :: TileKind -> Int
kindRank (TileKind k)
  | k < 27    = (k `mod` 9) + 1
  | otherwise = (k - 27) + 1

windKind :: Wind -> TileKind
windKind East  = TileKind 27
windKind South = TileKind 28
windKind West  = TileKind 29
windKind North = TileKind 30

parseWind :: String -> Maybe Wind
parseWind "E" = Just East
parseWind "S" = Just South
parseWind "W" = Just West
parseWind "N" = Just North
parseWind _   = Nothing

isSuit :: TileKind -> Bool
isSuit (TileKind k) = k < 27

isHonor :: TileKind -> Bool
isHonor (TileKind k) = k >= 27

isTerminal :: TileKind -> Bool
isTerminal k = isSuit k && (r == 1 || r == 9)
  where r = kindRank k

isSimple :: TileKind -> Bool
isSimple k = isSuit k && r >= 2 && r <= 8
  where r = kindRank k

isYaochu :: TileKind -> Bool
isYaochu k = isHonor k || isTerminal k

isWind :: TileKind -> Bool
isWind (TileKind k) = k >= 27 && k <= 30

isDragon :: TileKind -> Bool
isDragon (TileKind k) = k >= 31 && k <= 33

-- | All green tiles: 2s, 3s, 4s, 6s, 8s, Hatsu (6z).
isGreen :: TileKind -> Bool
isGreen (TileKind k) = k == 19 || k == 20 || k == 21 || k == 23 || k == 25 || k == 32

doraNext :: TileKind -> TileKind
doraNext (TileKind k)
  | k < 27 =
      let base = (k `div` 9) * 9
          off  = (k `mod` 9 + 1) `mod` 9
      in TileKind (base + off)
  | k <= 30 = TileKind (27 + ((k - 27 + 1) `mod` 4))
  | otherwise = TileKind (31 + ((k - 31 + 1) `mod` 3))

suitChar :: Suit -> Char
suitChar Man   = 'm'
suitChar Pin   = 'p'
suitChar Sou   = 's'
suitChar Honor = 'z'

tileDigitChar :: Tile -> Char
tileDigitChar (Tile k red)
  | red       = '0'
  | otherwise = toEnum (fromEnum '0' + kindRank k)

formatKind :: TileKind -> String
formatKind k = [toEnum (fromEnum '0' + kindRank k), suitChar (kindSuit k)]

formatKinds :: [TileKind] -> String
formatKinds [] = "-"
formatKinds ks = formatTiles (map (`Tile` False) ks)

formatTile :: Tile -> String
formatTile t = [tileDigitChar t, suitChar (kindSuit (tileKind t))]

formatTiles :: [Tile] -> String
formatTiles [] = "-"
formatTiles ts = concatMap fmtGroup (groupBy sameSuit (sort ts))
  where
    sameSuit a b = kindSuit (tileKind a) == kindSuit (tileKind b)
    fmtGroup gs@(g : _) = map tileDigitChar gs ++ [suitChar (kindSuit (tileKind g))]
    fmtGroup []         = ""

parseSuitChar :: Char -> Maybe Suit
parseSuitChar 'm' = Just Man
parseSuitChar 'p' = Just Pin
parseSuitChar 's' = Just Sou
parseSuitChar 'z' = Just Honor
parseSuitChar _   = Nothing

parseTiles :: String -> Either String [Tile]
parseTiles "-" = Right []
parseTiles ""  = Right []
parseTiles s   = go [] s
  where
    go [] [] = Right []
    go _  [] = Left "dangling_digits"
    go digits (c : cs)
      | isDigit c = go (c : digits) cs
      | otherwise = case parseSuitChar c of
          Nothing -> Left ("bad_suit:" ++ [c])
          Just suit -> do
            whenEmpty digits
            ts <- mapM (mkTile suit) (reverse digits)
            rest <- go [] cs
            Right (ts ++ rest)
    whenEmpty [] = Left "missing_digits"
    whenEmpty _  = Right ()
    mkTile Honor '0' = Left "red_honor"
    mkTile suit  '0' = Right (Tile (mkKind suit 5) True)
    mkTile Honor d
      | r >= 1 && r <= 7 = Right (Tile (mkKind Honor r) False)
      | otherwise        = Left "bad_honor_rank"
      where r = digitToInt d
    mkTile suit d
      | r >= 1 && r <= 9 = Right (Tile (mkKind suit r) False)
      | otherwise        = Left "bad_rank"
      where r = digitToInt d

parseTile :: String -> Either String Tile
parseTile s = case parseTiles s of
  Right [t] -> Right t
  Right _   -> Left "expected_single_tile"
  Left err  -> Left err

isOpenMeld :: Meld -> Bool
isOpenMeld m = meldKind m /= Ankan

isKanMeld :: Meld -> Bool
isKanMeld m = case meldKind m of
  Daiminkan  -> True
  Shouminkan -> True
  Ankan      -> True
  _          -> False

parseMeld :: String -> Either String Meld
parseMeld [] = Left "empty_meld"
parseMeld (c : rest) = do
  mk <- case c of
    'c' -> Right Chi
    'p' -> Right Pon
    'k' -> Right Daiminkan
    's' -> Right Shouminkan
    'a' -> Right Ankan
    _   -> Left ("bad_meld_prefix:" ++ [c])
  ts <- parseTiles rest
  Right (Meld mk (sort ts))

parseMelds :: String -> Either String [Meld]
parseMelds "-" = Right []
parseMelds ""  = Right []
parseMelds s   = mapM parseMeld (splitComma s)
  where
    splitComma [] = []
    splitComma xs =
      let (a, b) = break (== ',') xs
      in a : case b of
        []       -> []
        (_ : ys) -> splitComma ys

countsEmpty :: Counts
countsEmpty = accumArray (+) 0 (0, 33) []

countsFromKinds :: [TileKind] -> Counts
countsFromKinds ks = accumArray (+) 0 (0, 33) [(unKind k, 1) | k <- ks]

countsFromTiles :: [Tile] -> Counts
countsFromTiles ts = accumArray (+) 0 (0, 33) [(unKind (tileKind t), 1) | t <- ts]

countsAdd :: TileKind -> Int -> Counts -> Counts
countsAdd (TileKind k) delta c = c // [(k, c ! k + delta)]

countsAt :: Counts -> TileKind -> Int
countsAt c (TileKind k) = c ! k

countsTotal :: Counts -> Int
countsTotal c = go 0 0
  where
    go 34 acc = acc
    go i  acc = go (i + 1) (acc + c ! i)

allHandMeldsCounts :: [Tile] -> [Meld] -> Counts
allHandMeldsCounts hand melds =
  countsFromTiles (hand ++ concatMap meldTiles melds)
