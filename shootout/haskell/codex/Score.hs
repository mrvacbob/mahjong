module Score (Method(..), score, canWin) where

import Data.List (delete, group, maximumBy, sort)
import Data.Ord (Down(..), comparing)
import Shape
import Tiles

data Method = Ron | Tsumo deriving (Eq)

data SetType = Run | Pung | Quad deriving (Eq)
data Set = Set
    { setKind :: Kind
    , setType :: SetType
    , concealed :: Bool
    }

data Wait = Single | DoublePair | Inside | Edge | TwoSided deriving (Eq)

data Pattern = Normal Kind [Set] Wait | Pairs | Kokushi

data Win = Win
    { patternOf :: Pattern
    , allTiles :: [Tile]
    , winningKind :: Kind
    , closed :: Bool
    , method :: Method
    , context :: Context
    }

interpretations :: Context -> [Tile] -> [Meld] -> Tile -> Method -> [Shape] -> [Win]
interpretations ctx hand melds tile how forms =
    [ Win pattern tiles k (isClosed melds) how ctx
    | k <- winningKinds, form <- forms, pattern <- readForm k form ]
  where
    finished = tile : hand
    tiles = finished ++ concatMap meldTiles melds
    winningKinds
        | "tenhou" `elem` flags ctx = unique (map kind finished)
        | otherwise = [kind tile]
    readForm _ SevenPairs = [Pairs]
    readForm _ Orphans = [Kokushi]
    readForm k (Standard groups) =
        [ Normal headKind (setsAt i) (waitType k g)
        | Group headKind Pair <- groups, (i,g) <- indexed, k `elem` groupKinds g ]
      where
        indexed = zip [0 :: Int ..] groups
        setsAt i =
            [ Set p (if ty == Sequence then Run else Pung) (how == Tsumo || i /= j)
            | (j,Group p ty) <- indexed, ty /= Pair ]
            ++ [ Set (kind t) (declaredType m) (call m == ClosedKan)
               | m <- melds, t:_ <- [meldTiles m] ]
    declaredType m
        | call m == Chi = Run
        | isKan m = Quad
        | otherwise = Pung

waitType :: Kind -> Group -> Wait
waitType _ (Group _ Pair) = Single
waitType _ (Group _ Triplet) = DoublePair
waitType k (Group start Sequence)
    | k == start+1 = Inside
    | (rank start == 1 && k == start+2) || (rank start == 7 && k == start) = Edge
    | otherwise = TwoSided

pairFu :: Context -> Kind -> Int
pairFu ctx k = 2 * length (filter (==k) ([31..33] ++ [seat ctx, roundWind ctx]))

pinfu :: Win -> Bool
pinfu w = closed w && case patternOf w of
    Normal p sets wait -> wait == TwoSided && all ((== Run) . setType) sets
                          && pairFu (context w) p == 0
    _ -> False

fu :: Win -> Int
fu w = case patternOf w of
    Pairs -> 25
    Kokushi -> 0
    Normal p sets wait
        | selfDraw && pinfu w -> 20
        | otherwise -> max 30 (roundUp 10 (20 + methodFu + pairFu (context w) p
                                          + sum (map setFu sets) + waitFu wait))
  where
    selfDraw = method w == Tsumo
    methodFu
        | selfDraw = 2
        | closed w = 10
        | otherwise = 0
    waitFu wait = if wait `elem` [Single, Inside, Edge] then 2 else 0
    setFu (Set _ Run _) = 0
    setFu (Set k ty hidden) =
        product [2, if outside k then 2 else 1, if hidden then 2 else 1,
                 if ty == Quad then 4 else 1]

type Yaku = [(String, Int)]

awarded :: [(String, Int, Bool)] -> Yaku
awarded rules = [(name, value) | (name, value, applies) <- rules, applies]

ordinary :: Win -> Yaku
ordinary w = awarded
    [ ("riichi", 1, hasFlag "riichi" && not (hasFlag "double_riichi"))
    , ("double_riichi", 2, hasFlag "double_riichi")
    , ("ippatsu", 1, hasFlag "ippatsu")
    , ("tsumo", 1, closed w && method w == Tsumo)
    , ("haitei", 1, hasFlag "haitei")
    , ("houtei", 1, hasFlag "houtei")
    , ("rinshan", 1, hasFlag "rinshan")
    , ("chankan", 1, hasFlag "chankan")
    , ("tanyao", 1, all (not . outside) ks)
    , ("honroutou", 2, all outside ks)
    , ("honitsu", openReduced 3, oneSuit && any honor ks)
    , ("chinitsu", openReduced 6, oneSuit && not (any honor ks))
    ] ++ case patternOf w of
        Pairs -> [("chiitoi",2)]
        Kokushi -> []
        Normal p sets _ -> standardYaku p sets
  where
    ctx = context w
    hasFlag = flip elem (flags ctx)
    ks = map kind (allTiles w)
    oneSuit = length (unique (map suit (filter (not . honor) ks))) == 1
    openReduced n = if closed w then n else n-1
    standardYaku p sets = awarded
        [ ("pinfu", 1, pinfu w)
        , ("iipeikou", 1, closed w && repeatedRuns == 1)
        , ("ryanpeikou", 3, closed w && repeatedRuns == 2)
        , ("yakuhai_haku", 1, 31 `elem` pungs)
        , ("yakuhai_hatsu", 1, 32 `elem` pungs)
        , ("yakuhai_chun", 1, 33 `elem` pungs)
        , ("yakuhai_seat", 1, seat ctx `elem` pungs)
        , ("yakuhai_round", 1, roundWind ctx `elem` pungs)
        , ("toitoi", 2, null runs)
        , ("sanankou", 2, length [() | Set _ ty True <- sets, ty /= Run] >= 3)
        , ("sanshoku", openReduced 2, acrossSuits runs)
        , ("sanshoku_doukou", 2, acrossSuits pungs)
        , ("ittsu", openReduced 2, any (\k -> all (`elem` runs) [k,k+3,k+6]) [0,9,18])
        , ("chanta", openReduced 2, mixedOutside && any honor ks)
        , ("junchan", openReduced 3, mixedOutside && not (any honor ks))
        , ("shousangen", 2, p >= 31 && length (filter (>=31) pungs) == 2)
        , ("sankantsu", 2, length [() | Set _ Quad _ <- sets] == 3)
        ]
      where
        runs = map setKind (filter ((== Run) . setType) sets)
        pungs = map setKind (filter ((/= Run) . setType) sets)
        repeatedRuns = sum (map ((`div` 2) . length) (group (sort runs)))
        acrossSuits starts = any (\k -> all (`elem` starts) [k,k+9,k+18]) [0..8]
        mixedOutside = outside p && all outside pungs && not (null runs)
                       && all (\k -> terminal k || terminal (k+2)) runs

limits :: Win -> Yaku
limits w = awarded
    [ ("tenhou", 1, hasFlag "tenhou")
    , ("chiihou", 1, hasFlag "chiihou")
    , ("tsuuiisou", 1, all honor ks)
    , ("chinroutou", 1, all terminal ks)
    , ("ryuuiisou", 1, all (`elem` [19,20,21,23,25,32]) ks)
    , ("junsei_chuuren", 2, nineGates && nineWay)
    , ("chuuren", 1, nineGates && not nineWay)
    ] ++ case patternOf w of
        Kokushi -> if copies cs winning == 2 then [("kokushi_13",2)] else [("kokushi",1)]
        Pairs -> []
        Normal p sets wait -> awarded
            [ ("daisangen", 1, length (filter (>=31) pungs) == 3)
            , ("shousuushii", 1, winds == 3 && p >= 27 && p < 31)
            , ("daisuushii", 2, winds == 4)
            , ("suukantsu", 1, length [() | Set _ Quad _ <- sets] == 4)
            , ("suuankou", 1, fourConcealed && wait == DoublePair)
            , ("suuankou_tanki", 2, fourConcealed && wait == Single)
            ]
          where
            pungs = [k | Set k ty _ <- sets, ty /= Run]
            winds = length [k | k <- pungs, k >= 27, k < 31]
            fourConcealed = all (\s -> setType s /= Run && concealed s) sets
  where
    hasFlag = flip elem (flags (context w))
    ks = map kind (allTiles w)
    cs = counts ks
    winning = winningKind w
    gates = concat [replicate (if r `elem` [1,9] then 3 else 1) r | r <- [1..9]]
    nineGates = closed w && length ks == 14 && suit winning < 3
        && all ((==suit winning) . suit) ks
        && and [copies cs (9*suit winning + r-1) >= length (filter (==r) gates) | r <- [1..9]]
    nineWay = sort (map rank (delete winning ks)) == gates

bonus :: Win -> Yaku
bonus w = [(name,n) | (name,n) <- [("aka",aka),("dora",dora),("ura",ura)], n > 0]
  where
    ctx = context w
    cs = counts (map kind (allTiles w))
    countDora = sum . map (copies cs . doraKind . kind)
    aka = length (filter red (allTiles w))
    dora = countDora (indicators ctx)
    ura | any (`elem` flags ctx) ["riichi","double_riichi"] = countDora (uraIndicators ctx)
        | otherwise = 0

roundUp :: Int -> Int -> Int
roundUp unit n = ((n + unit - 1) `div` unit) * unit

basicPoints :: Int -> Int -> Int
basicPoints han f
    | han >= 13 = 8000
    | han >= 11 = 6000
    | han >= 8 = 4000
    | han >= 6 = 3000
    | han >= 5 = 2000
    | otherwise = min 2000 (f * 2^(han+2))

payment :: Win -> Int -> (String, Int)
payment w basic = case method w of
    Ron -> let bill = roundUp 100 (basic * if dealer then 6 else 4) + 300*h
           in ("ron:" ++ show bill, bill)
    Tsumo | dealer -> ("all:" ++ show high, 3*high)
          | otherwise -> ("tsumo:" ++ show low ++ "/" ++ show high, 2*low+high)
  where
    dealer = seat (context w) == 27
    h = honba (context w)
    high = roundUp 100 (2*basic) + 100*h
    low = roundUp 100 basic + 100*h

yakuText :: Yaku -> String
yakuText ys = join ',' [name ++ ":" ++ show n | (name,n) <- sort ys]

data Result = Result
    { names :: String
    , multiple :: Int
    , han :: Int
    , minipoints :: Int
    , pay :: String
    , total :: Int
    }

evaluate :: Win -> [Result]
evaluate w
    | not (null yakuman) = [result yakuman (sum (map snd yakuman)) 0 0]
    | not (null normal) = [result full 0 (sum (map snd full)) (fu w)]
    | otherwise = []
  where
    yakuman = limits w
    normal = ordinary w
    full = normal ++ bonus w
    result ys m h f = Result (yakuText ys) m h f paymentText points
      where
        (paymentText, points) = payment w (if m > 0 then 8000*m else basicPoints h f)

showResult :: Result -> String
showResult r = "yaku=" ++ names r ++ value
    ++ " pay=" ++ pay r ++ " total=" ++ show (total r)
  where
    value | multiple r > 0 = " yakuman=" ++ show (multiple r)
          | otherwise = " han=" ++ show (han r) ++ " fu=" ++ show (minipoints r)

score :: Context -> [Tile] -> [Meld] -> Tile -> Method -> String
score ctx hand melds tile how
    | null forms = "error=not_agari"
    | null results = "error=no_yaku"
    | otherwise = showResult (maximumBy (comparing priority) results)
  where
    forms = shapes (length melds) (counts (map kind (tile:hand)))
    results = concatMap evaluate (interpretations ctx hand melds tile how forms)
    priority r = (total r, multiple r > 0, han r, minipoints r, Down (names r))

canWin :: Context -> [Tile] -> [Meld] -> Tile -> Method -> Bool
canWin ctx hand melds tile how =
    any (\w -> not (null (limits w) && null (ordinary w))) wins
  where
    forms = shapes (length melds) (counts (map kind (tile:hand)))
    wins = interpretations ctx hand melds tile how forms
