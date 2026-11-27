-- | Scoring a won hand: readings, yaku and yakuman tables, fu, payment.
module Score
  ( Flag (..), parseFlag
  , Situation (..), defaultSituation
  , Score (..), Value (..), Payment (..), ScoreError (..)
  , score, showScore
  ) where

import Tile
import Meld
import Hand
import Data.List (delete, intercalate, maximumBy, nub, sortOn)
import Data.Ord (comparing, Down (..))
import qualified Data.Set as S

data Flag
  = Riichi | DoubleRiichi | Ippatsu | Haitei | Houtei | Rinshan | Chankan
  | Tenhou | Chiihou | AnkanRob
  deriving (Eq, Ord, Show, Enum, Bounded)

parseFlag :: String -> Maybe Flag
parseFlag s = lookup s
  [ ("riichi", Riichi), ("double_riichi", DoubleRiichi), ("ippatsu", Ippatsu)
  , ("haitei", Haitei), ("houtei", Houtei), ("rinshan", Rinshan), ("chankan", Chankan)
  , ("tenhou", Tenhou), ("chiihou", Chiihou), ("ankan_rob", AnkanRob) ]

-- | Everything @score@ is told about a win.
data Situation = Situation
  { hand :: [Tile]          -- ^ concealed tiles, without the winning tile
  , melds :: [Meld]
  , winTile :: Tile
  , byTsumo :: Bool
  , seatWind :: Kind
  , roundWind :: Kind
  , doraInd :: [Tile]
  , uraInd :: [Tile]
  , honba :: Int
  , flags :: S.Set Flag
  }

defaultSituation :: Situation
defaultSituation = Situation [] [] (Tile (Kind Honor 1) False) False east east [] [] 0 S.empty
  where east = Kind Honor 1

isDealer :: Situation -> Bool
isDealer s = seatWind s == Kind Honor 1

isClosed :: Situation -> Bool
isClosed = not . any isOpenMeld . melds

------------------------------------------------------------------------------
-- Readings

data Wait = Ryanmen | Kanchan | Penchan | Shanpon | Tanki
  deriving (Eq, Ord, Show)

-- | One interpretation of the hand.
data Reading
  = Standard [Group] Wait   -- ^ all five groups, melds included
  | SevenPairs
  | Thirteen Bool           -- ^ kokushi; True for the 13-sided wait
  deriving (Eq, Ord, Show)

-- | A reading together with what the yaku predicates need to know.
data Win = Win
  { sit :: Situation
  , reading :: Reading
  , winKind :: Kind
  , hand13 :: [Kind]        -- ^ concealed kinds without the winning tile
  , tiles :: [Kind]         -- ^ every tile of the hand, melds included
  }

-- | The ways the winning tile can complete this group, as waits.
waitsIn :: Kind -> Group -> [Wait]
waitsIn w (Group f k _) = case f of
  Pair | k == w -> [Tanki]
  Triplet | k == w -> [Shanpon]
  Run | suit w == suit k, d >= 0, d <= 2 -> [runWait d]
  _ -> []
  where
    d = num w - num k
    runWait 1 = Kanchan
    runWait 0 | num k == 7 = Penchan
    runWait 2 | num k == 1 = Penchan
    runWait _ = Ryanmen

-- | All readings with the given winning kind.
readingsWith :: Situation -> Kind -> [Kind] -> [Reading]
readingsWith s w h13 = nub (standard ++ pairs ++ kokushi)
  where
    concealed = w : h13
    meldGroups = map meldGroup (melds s)
    noMelds = null (melds s)
    standard =
      [ Standard (meldGroups ++ completed g wait ++ delete g gs) wait
      | gs <- decompose concealed
      , g <- nub gs
      , wait <- waitsIn w g ]
    -- A shanpon triplet completed by ron counts as open.
    completed g wait
      | wait == Shanpon && not (byTsumo s) = [g { gopen = True }]
      | otherwise = [g]
    pairs = [SevenPairs | noMelds, isChiitoi concealed]
    kokushi = [Thirteen (length (nub (filter isYaochu h13)) == 13) | noMelds, isKokushi concealed]

-- | Every (reading, winning kind, hand13). Tenhou may pick any of its 14 tiles.
wins :: Situation -> [Win]
wins s =
  [ Win s r w h13 allTiles
  | (w, h13) <- choices
  , r <- readingsWith s w h13 ]
  where
    concealed = map kind (winTile s : hand s)
    allTiles = concealed ++ concatMap (map kind . mtiles) (melds s)
    choices
      | Tenhou `S.member` flags s = [(w, delete w concealed) | w <- nub concealed]
      | otherwise = [(kind (winTile s), map kind (hand s))]

------------------------------------------------------------------------------
-- Predicate helpers

flag :: Flag -> Win -> Bool
flag f = S.member f . flags . sit

-- | Lift a predicate on the groups of a standard reading; False otherwise.
std :: ([Group] -> Bool) -> Win -> Bool
std p w = case reading w of
  Standard gs _ -> p gs
  _ -> False

-- | Like 'std' with access to the whole win.
stdW :: (Win -> [Group] -> Bool) -> Win -> Bool
stdW p w = std (p w) w

count :: (a -> Bool) -> [a] -> Int
count p = length . filter p

setOf :: Kind -> [Group] -> Bool
setOf k = any (\g -> isSetLike g && gbase g == k)

concealedSets :: [Group] -> Int
concealedSets = count (\g -> isSetLike g && not (gopen g))

kans :: [Group] -> Int
kans = count ((== Quad) . gform)

runs :: [Group] -> [Group]
runs = filter ((== Run) . gform)

-- | Number of pairs of identical runs (closed hands only use this).
peikou :: [Group] -> Int
peikou gs = sum [count (== b) bases `div` 2 | b <- nub bases]
  where bases = map gbase (runs gs)

hasYaochu, hasTerminal :: Group -> Bool
hasYaochu g = any isYaochu (groupKinds g)
hasTerminal g = any isTerminal (groupKinds g)

dragons, winds :: [Kind]
dragons = [Kind Honor n | n <- [5 .. 7]]
winds = [Kind Honor n | n <- [1 .. 4]]

pairKind :: [Group] -> [Kind]
pairKind gs = [gbase g | g <- gs, gform g == Pair]

-- | All number tiles from one suit?
oneSuit :: [Kind] -> Bool
oneSuit ks = case nub [suit k | k <- ks, not (isHonor k)] of
  [_] -> True
  _ -> False

isValuePair :: Win -> Kind -> Bool
isValuePair w k = isDragon k || k == seatWind (sit w) || k == roundWind (sit w)

waitOf :: Win -> Maybe Wait
waitOf w = case reading w of
  Standard _ wt -> Just wt
  _ -> Nothing

------------------------------------------------------------------------------
-- Yaku tables. Each entry reads like the rule it implements.

data Yaku = Yaku { yName :: String, closedHan :: Int, openHan :: Maybe Int, holds :: Win -> Bool }

closedOnly :: String -> Int -> (Win -> Bool) -> Yaku
closedOnly n h = Yaku n h Nothing

yaku :: String -> Int -> Int -> (Win -> Bool) -> Yaku
yaku n c o = Yaku n c (Just o)

yakuTable :: [Yaku]
yakuTable =
  [ closedOnly "riichi" 1 $ \w -> flag Riichi w && not (flag DoubleRiichi w)
  , closedOnly "double_riichi" 2 $ flag DoubleRiichi
  , closedOnly "ippatsu" 1 $ flag Ippatsu
  , closedOnly "tsumo" 1 $ byTsumo . sit
  , closedOnly "pinfu" 1 $ stdW $ \w gs ->
      length (runs gs) == 4 && not (any (isValuePair w) (pairKind gs)) && waitOf w == Just Ryanmen
  , yaku "tanyao" 1 1 $ all isSimple . tiles
  , closedOnly "iipeikou" 1 $ std $ \gs -> peikou gs == 1
  , yaku "yakuhai_haku" 1 1 $ std $ setOf (Kind Honor 5)
  , yaku "yakuhai_hatsu" 1 1 $ std $ setOf (Kind Honor 6)
  , yaku "yakuhai_chun" 1 1 $ std $ setOf (Kind Honor 7)
  , yaku "yakuhai_seat" 1 1 $ stdW $ \w -> setOf (seatWind (sit w))
  , yaku "yakuhai_round" 1 1 $ stdW $ \w -> setOf (roundWind (sit w))
  , yaku "haitei" 1 1 $ flag Haitei
  , yaku "houtei" 1 1 $ flag Houtei
  , yaku "rinshan" 1 1 $ flag Rinshan
  , yaku "chankan" 1 1 $ flag Chankan
  , closedOnly "chiitoi" 2 $ (== SevenPairs) . reading
  , yaku "toitoi" 2 2 $ std $ \gs -> count isSetLike gs == 4
  , yaku "sanankou" 2 2 $ std $ \gs -> concealedSets gs == 3
  , yaku "sanshoku" 2 1 $ std $ \gs ->
      any (\n -> all (\s -> any ((== Kind s n) . gbase) (runs gs)) numberSuits) [1 .. 7]
  , yaku "sanshoku_doukou" 2 2 $ std $ \gs ->
      any (\n -> all (\s -> setOf (Kind s n) gs) numberSuits) [1 .. 9]
  , yaku "ittsu" 2 1 $ std $ \gs ->
      any (\s -> all (\n -> any ((== Kind s n) . gbase) (runs gs)) [1, 4, 7]) numberSuits
  , yaku "chanta" 2 1 $ std $ \gs ->
      all hasYaochu gs && not (null (runs gs)) && any (isHonor . gbase) gs
  , yaku "honroutou" 2 2 $ \w -> all isYaochu (tiles w) && any isHonor (tiles w) && any isTerminal (tiles w)
  , yaku "shousangen" 2 2 $ std $ \gs ->
      count (`setOf` gs) dragons == 2 && any isDragon (pairKind gs)
  , yaku "sankantsu" 2 2 $ std $ \gs -> kans gs == 3
  , yaku "honitsu" 3 2 $ \w -> oneSuit (tiles w) && any isHonor (tiles w)
  , yaku "junchan" 3 2 $ std $ \gs ->
      all hasTerminal gs && not (null (runs gs)) && not (any (isHonor . gbase) gs)
  , closedOnly "ryanpeikou" 3 $ std $ \gs -> peikou gs == 2
  , yaku "chinitsu" 6 5 $ \w -> oneSuit (tiles w) && not (any isHonor (tiles w))
  ]

data Yakuman = Yakuman { ymName :: String, multiple :: Int, ymHolds :: Win -> Bool }

-- | Nine gates: the concealed 14 of one suit, no melds, holding 1112345678999.
chuurenShape :: Win -> Bool
chuurenShape w =
  null (melds (sit w)) && oneSuit ks && not (any isHonor ks)
    && and (zipWith (>=) (counts ks) [3, 1, 1, 1, 1, 1, 1, 1, 3])
  where ks = winKind w : hand13 w

counts :: [Kind] -> [Int]
counts ks = [count ((== n) . num) ks | n <- [1 .. 9]]

pureNineGates :: Win -> Bool
pureNineGates w = counts (hand13 w) == [3, 1, 1, 1, 1, 1, 1, 1, 3]

yakumanTable :: [Yakuman]
yakumanTable =
  [ Yakuman "kokushi" 1 $ (== Thirteen False) . reading
  , Yakuman "kokushi_13" 2 $ (== Thirteen True) . reading
  , Yakuman "suuankou" 1 $ \w -> std (\gs -> concealedSets gs == 4) w && waitOf w /= Just Tanki
  , Yakuman "suuankou_tanki" 2 $ \w -> std (\gs -> concealedSets gs == 4) w && waitOf w == Just Tanki
  , Yakuman "daisangen" 1 $ std $ \gs -> all (`setOf` gs) dragons
  , Yakuman "shousuushii" 1 $ std $ \gs -> count (`setOf` gs) winds == 3 && any isWind (pairKind gs)
  , Yakuman "daisuushii" 2 $ std $ \gs -> all (`setOf` gs) winds
  , Yakuman "tsuuiisou" 1 $ all isHonor . tiles
  , Yakuman "chinroutou" 1 $ all isTerminal . tiles
  , Yakuman "ryuuiisou" 1 $ all isGreen . tiles
  , Yakuman "chuuren" 1 $ \w -> chuurenShape w && not (pureNineGates w)
  , Yakuman "junsei_chuuren" 2 $ \w -> chuurenShape w && pureNineGates w
  , Yakuman "suukantsu" 1 $ std $ \gs -> kans gs == 4
  , Yakuman "tenhou" 1 $ flag Tenhou
  , Yakuman "chiihou" 1 $ flag Chiihou
  ]

------------------------------------------------------------------------------
-- Fu

fu :: Win -> [(String, Int)] -> Int
fu w yakus = case reading w of
  SevenPairs -> 25
  Thirteen _ -> 0
  Standard gs wt
    | pinfu && tsumo -> 20
    | otherwise -> let r = roundUp (20 + menzenRon + tsumoFu + sum (map groupFu gs) + waitFu wt)
                   in if r == 20 then 30 else r          -- open hand, no fu, ron
  where
    s = sit w
    tsumo = byTsumo s
    pinfu = "pinfu" `elem` map fst yakus
    menzenRon = if isClosed s && not tsumo then 10 else 0
    tsumoFu = if tsumo then 2 else 0
    groupFu (Group f k open) = case f of
      Pair -> (if isDragon k then 2 else 0) + (if k == seatWind s then 2 else 0) + (if k == roundWind s then 2 else 0)
      Run -> 0
      Triplet -> setFu 1
      Quad -> setFu 4
      where setFu m = m * (if isYaochu k then 4 else 2) * (if open then 1 else 2)
    waitFu wt = if wt `elem` [Kanchan, Penchan, Tanki] then 2 else 0
    roundUp x = (x + 9) `div` 10 * 10

------------------------------------------------------------------------------
-- Evaluation

data Value = Yakuman' Int | Ordinary Int Int     -- ^ multiple, or han and fu
  deriving (Eq, Show)

data Payment = Ron Int | All Int | Split Int Int  -- ^ Split non-dealer dealer
  deriving (Eq, Show)

data Score = Score { yakuOf :: [(String, Int)], value :: Value, payment :: Payment, total :: Int }
  deriving (Eq, Show)

data ScoreError = NotAgari | NoYaku
  deriving (Eq, Show)

-- | The value of one reading, or Nothing if it has no yaku.
evaluate :: Win -> Maybe Score
evaluate w
  | not (null yakuman) =
      let n = sum (map snd yakuman) in Just (priced (sortOn fst yakuman) (Yakuman' n) (8000 * n))
  | null yakus = Nothing
  | otherwise = Just (priced yakuList (Ordinary han f) (basic han f))
  where
    s = sit w
    closed = isClosed s
    yakuman = [(ymName y, multiple y) | y <- yakumanTable, ymHolds y w]
    yakus = [(yName y, h) | y <- yakuTable, holds y w, Just h <- [if closed then Just (closedHan y) else openHan y]]
    allTiles = winTile s : hand s ++ concatMap mtiles (melds s)
    doraCount inds = sum [count ((== doraOf i) . kind) allTiles | i <- inds]
    riichi = any (`S.member` flags s) [Riichi, DoubleRiichi]
    bonus = filter ((> 0) . snd)
      [ ("dora", doraCount (doraInd s))
      , ("aka", count red allTiles)
      , ("ura", if riichi then doraCount (uraInd s) else 0) ]
    yakuList = sortOn fst (yakus ++ bonus)
    han = sum (map snd yakuList)
    f = fu w yakus
    priced ys v b = let p = pay s b in Score ys v p (payTotal p)

basic :: Int -> Int -> Int
basic han f
  | han >= 13 = 8000
  | han >= 11 = 6000
  | han >= 8 = 4000
  | han >= 6 = 3000
  | han >= 5 = 2000
  | otherwise = min 2000 (f * 2 ^ (2 + han))

pay :: Situation -> Int -> Payment
pay s b = case (byTsumo s, isDealer s) of
  (False, True) -> Ron (up (6 * b) + 300 * h)
  (False, False) -> Ron (up (4 * b) + 300 * h)
  (True, True) -> All (up (2 * b) + 100 * h)
  (True, False) -> Split (up b + 100 * h) (up (2 * b) + 100 * h)
  where
    h = honba s
    up x = (x + 99) `div` 100 * 100

payTotal :: Payment -> Int
payTotal p = case p of
  Ron n -> n
  All n -> 3 * n
  Split a b -> 2 * a + b

-- | Best interpretation: highest total, then a real yakuman over kazoe, then han,
-- fu, and the yaku list that sorts first.
score :: Situation -> Either ScoreError Score
score s = case (ws, scored) of
  ([], _) -> Left NotAgari
  (_, []) -> Left NoYaku
  _ -> Right (maximumBy (comparing key) scored)
  where
    ws = wins s
    scored = [sc | Just sc <- map evaluate ws]
    key sc = (total sc, isYakuman (value sc), han (value sc), fuOf (value sc), Down (showYaku (yakuOf sc)))
    isYakuman (Yakuman' _) = True
    isYakuman _ = False
    han (Ordinary h _) = h
    han _ = 0
    fuOf (Ordinary _ f) = f
    fuOf _ = 0

showYaku :: [(String, Int)] -> String
showYaku ys = intercalate "," [n ++ ":" ++ show h | (n, h) <- ys]

showScore :: Either ScoreError Score -> String
showScore (Left NotAgari) = "error=not_agari"
showScore (Left NoYaku) = "error=no_yaku"
showScore (Right sc) = unwords $
  ["yaku=" ++ showYaku (yakuOf sc)]
    ++ (case value sc of
          Yakuman' n -> ["yakuman=" ++ show n]
          Ordinary h f -> ["han=" ++ show h, "fu=" ++ show f])
    ++ ["pay=" ++ showPay (payment sc), "total=" ++ show (total sc)]
  where
    showPay (Ron n) = "ron:" ++ show n
    showPay (All n) = "all:" ++ show n
    showPay (Split a b) = "tsumo:" ++ show a ++ "/" ++ show b
