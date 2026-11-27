module Score
  ( WinBy (..)
  , Flag (..)
  , ScoreRequest (..)
  , ScoreResult (..)
  , parseFlag
  , parseFlags
  , scoreHand
  , formatScoreResult
  ) where

import Data.Bits (shiftL)
import Data.List (intercalate, nub, sort, sortOn)
import Data.Ord (Down (..))
import Data.Set (Set)
import qualified Data.Set as Set
import Agari
import Tile

data WinBy = Tsumo | Ron
  deriving (Eq, Ord, Show)

data Flag
  = FlagRiichi
  | FlagDoubleRiichi
  | FlagIppatsu
  | FlagHaitei
  | FlagHoutei
  | FlagRinshan
  | FlagChankan
  | FlagTenhou
  | FlagChiihou
  | FlagAnkanRob
  deriving (Eq, Ord, Show)

data ScoreRequest = ScoreRequest
  { srHand  :: ![Tile]
  , srMelds :: ![Meld]
  , srWin   :: !Tile
  , srBy    :: !WinBy
  , srSeat  :: !Wind
  , srRound :: !Wind
  , srDora  :: ![Tile]
  , srUra   :: ![Tile]
  , srHonba :: !Int
  , srFlags :: !(Set Flag)
  } deriving (Eq, Show)

data ScoreResult
  = ScoreError !String
  | ScoreOrdinary
      { soYaku  :: ![(String, Int)]
      , soHan   :: !Int
      , soFu    :: !Int
      , soPay   :: !String
      , soTotal :: !Int
      }
  | ScoreYakuman
      { syYaku  :: ![(String, Int)]
      , syMult  :: !Int
      , syPay   :: !String
      , syTotal :: !Int
      }
  deriving (Eq, Show)

data WaitType = Ryanmen | Shanpon | Kanchan | Penchan | Tanki
  deriving (Eq, Ord, Show)

data Mentsu = Mentsu
  { mKind :: !GroupKind   -- Seq | Triplet | Kan
  , mTile :: !TileKind    -- lowest tile for Seq, tile kind for Triplet/Kan
  , mOpen :: !Bool        -- True if open meld or triplet completed by ron
  } deriving (Eq, Ord, Show)

data HandShape
  = StandardShape
      { hsPair   :: !TileKind
      , hsMentsu :: ![Mentsu]
      , hsWait   :: !WaitType
      }
  | ChiitoiShape ![TileKind]
  | KokushiShape !Bool  -- True = 13-wait
  deriving (Eq, Show)

data ScoreCtx = ScoreCtx
  { scReq        :: !ScoreRequest
  , scWinKind    :: !TileKind
  , scIsClosed   :: !Bool
  , scConcealed  :: !Counts       -- concealed + win only
  , scAllKinds   :: ![TileKind]   -- distinct kinds present across hand+win+melds
  , scDoraCount  :: !Int
  , scAkaCount   :: !Int
  , scUraCount   :: !Int
  }

parseFlag :: String -> Either String Flag
parseFlag "riichi"        = Right FlagRiichi
parseFlag "double_riichi" = Right FlagDoubleRiichi
parseFlag "ippatsu"       = Right FlagIppatsu
parseFlag "haitei"        = Right FlagHaitei
parseFlag "houtei"        = Right FlagHoutei
parseFlag "rinshan"       = Right FlagRinshan
parseFlag "chankan"       = Right FlagChankan
parseFlag "tenhou"        = Right FlagTenhou
parseFlag "chiihou"       = Right FlagChiihou
parseFlag "ankan_rob"     = Right FlagAnkanRob
parseFlag s               = Left ("bad_flag:" ++ s)

parseFlags :: String -> Either String (Set Flag)
parseFlags "-" = Right Set.empty
parseFlags ""  = Right Set.empty
parseFlags s   = Set.fromList <$> mapM parseFlag (splitComma s)
  where
    splitComma [] = []
    splitComma xs =
      let (a, b) = break (== ',') xs
      in a : case b of
        []       -> []
        (_ : ys) -> splitComma ys

meldToMentsu :: Meld -> Mentsu
meldToMentsu m = case meldTiles m of
  (t : _) ->
    let k = tileKind t
    in case meldKind m of
      Chi        -> Mentsu Seq     k True
      Pon        -> Mentsu Triplet k True
      Daiminkan  -> Mentsu Kan     k True
      Shouminkan -> Mentsu Kan     k True
      Ankan      -> Mentsu Kan     k False
  [] -> error "meldToMentsu: empty meld"

-- | Expand a Decomp into all valid HandShape interpretations for a given winning tile.
expandDecomp :: [Meld] -> WinBy -> Counts -> TileKind -> Decomp -> [HandShape]
expandDecomp _ _ concealed winK KokushiDecomp =
  [KokushiShape (countsAt concealed winK == 2)]
expandDecomp _ _ _ _ (ChiitoiDecomp ps) =
  [ChiitoiShape ps]
expandDecomp melds winBy _ winK (StdDecomp pair cSets) =
  let meldMs = map meldToMentsu melds
      cMs = [Mentsu gk k False | CGroup k gk <- cSets]
      tankiShape =
        [ StandardShape pair (cMs ++ meldMs) Tanki
        | pair == winK
        ]
      setShapes =
        [ StandardShape pair (m' : rest ++ meldMs) wt
        | (idx, m) <- zip [0 :: Int ..] cMs
        , (m', wt) <- matchWinTile winBy winK m
        , let rest = take idx cMs ++ drop (idx + 1) cMs
        ]
  in tankiShape ++ setShapes

matchWinTile :: WinBy -> TileKind -> Mentsu -> [(Mentsu, WaitType)]
matchWinTile winBy winK m@(Mentsu Triplet k _)
  | k == winK = [(m { mOpen = winBy == Ron }, Shanpon)]
  | otherwise = []
matchWinTile _ winK m@(Mentsu Seq s _)
  | kindSuit s /= kindSuit winK = []
  | rW == rS + 1 = [(m, Kanchan)]
  | rW == rS     = [(m, if rS == 7 then Penchan else Ryanmen)]
  | rW == rS + 2 = [(m, if rS == 1 then Penchan else Ryanmen)]
  | otherwise    = []
  where
    rS = kindRank s
    rW = kindRank winK
matchWinTile _ _ _ = []

-- | Score a hand, handling tenhou's best-winning-tile rule.
scoreHand :: ScoreRequest -> ScoreResult
scoreHand req =
  let allConcealed = srWin req : srHand req
      concealedCounts = countsFromTiles allConcealed
      decomps = decompose concealedCounts (length (srMelds req))
  in if null decomps
       then ScoreError "not_agari"
       else
         let allTiles = allConcealed ++ concatMap meldTiles (srMelds req)
             fullCounts = countsFromTiles allTiles
             distinctKinds = [k | k <- allKinds, countsAt fullCounts k > 0]
             isClosed = not (any isOpenMeld (srMelds req))
             doraCnt = sum [countsAt fullCounts (doraNext (tileKind d)) | d <- srDora req]
             akaCnt  = length (filter tileRed allTiles)
             hasRiichi = Set.member FlagRiichi (srFlags req) || Set.member FlagDoubleRiichi (srFlags req)
             uraCnt =
               if hasRiichi
                 then sum [countsAt fullCounts (doraNext (tileKind u)) | u <- srUra req]
                 else 0
             winCandidates =
               if Set.member FlagTenhou (srFlags req)
                 then nub (sort (map tileKind allConcealed))
                 else [tileKind (srWin req)]
             results =
               [ scoreShape ctx shape
               | wk <- winCandidates
               , let ctx = ScoreCtx req wk isClosed concealedCounts distinctKinds doraCnt akaCnt uraCnt
               , d <- decomps
               , shape <- expandDecomp (srMelds req) (srBy req) concealedCounts wk d
               ]
             valid = [r | Just r <- results]
         in case valid of
              [] -> ScoreError "no_yaku"
              _  -> maximumByKey resultKey valid

maximumByKey :: Ord k => (a -> k) -> [a] -> a
maximumByKey f = foldr1 (\x y -> if f x >= f y then x else y)

-- | Tie-break order from spec/formats.md:
-- highest total, then real yakuman over kazoe, then higher han, then higher fu,
-- then yaku list that sorts first as a string.
resultKey :: ScoreResult -> (Int, Bool, Int, Int, Down String)
resultKey (ScoreYakuman ys _ _ tot) =
  (tot, True, 0, 0, Down (formatYakuList ys))
resultKey (ScoreOrdinary ys han fu _ tot) =
  (tot, False, han, fu, Down (formatYakuList ys))
resultKey (ScoreError _) =
  (-1, False, 0, 0, Down "")

scoreShape :: ScoreCtx -> HandShape -> Maybe ScoreResult
scoreShape ctx shape =
  let yms = evalYakuman ctx shape
  in if not (null yms)
       then
         let sortedYm = sortOn fst yms
             mult = sum (map snd sortedYm)
             (payStr, tot) = computePayment (scReq ctx) (8000 * mult)
         in Just (ScoreYakuman sortedYm mult payStr tot)
       else
         let baseYaku = evalStandardYaku ctx shape
         in if null baseYaku
              then Nothing
              else
                let doraYaku =
                      [("dora", scDoraCount ctx) | scDoraCount ctx > 0]
                      ++ [("aka", scAkaCount ctx) | scAkaCount ctx > 0]
                      ++ [("ura", scUraCount ctx) | scUraCount ctx > 0]
                    allYaku = sortOn fst (baseYaku ++ doraYaku)
                    han = sum (map snd allYaku)
                    hasPinfu = any ((== "pinfu") . fst) baseYaku
                    fu = computeFu ctx shape hasPinfu
                    basic = ordinaryBasic han fu
                    (payStr, tot) = computePayment (scReq ctx) basic
                in Just (ScoreOrdinary allYaku han fu payStr tot)

-- =========================================================================
-- Declarative Yakuman Rules
-- =========================================================================

evalYakuman :: ScoreCtx -> HandShape -> [(String, Int)]
evalYakuman ctx shape = concatMap (\rule -> rule ctx shape) yakumanRules

yakumanRules :: [ScoreCtx -> HandShape -> [(String, Int)]]
yakumanRules =
  [ ymTenhou
  , ymChiihou
  , ymKokushi
  , ymSuuankou
  , ymDaisangen
  , ymSuushii
  , ymTsuuiisou
  , ymChinroutou
  , ymRyuuiisou
  , ymChuuren
  , ymSuukantsu
  ]

ymTenhou, ymChiihou, ymKokushi, ymSuuankou, ymDaisangen, ymSuushii :: ScoreCtx -> HandShape -> [(String, Int)]
ymTsuuiisou, ymChinroutou, ymRyuuiisou, ymChuuren, ymSuukantsu :: ScoreCtx -> HandShape -> [(String, Int)]

ymTenhou ctx _ = [("tenhou", 1) | Set.member FlagTenhou (srFlags (scReq ctx))]
ymChiihou ctx _ = [("chiihou", 1) | Set.member FlagChiihou (srFlags (scReq ctx))]

ymKokushi _ (KokushiShape True)  = [("kokushi_13", 2)]
ymKokushi _ (KokushiShape False) = [("kokushi", 1)]
ymKokushi _ _                    = []

ymSuuankou _ (StandardShape _ ms wt)
  | length (filter isClosedTriOrKan ms) == 4 =
      if wt == Tanki then [("suuankou_tanki", 2)] else [("suuankou", 1)]
ymSuuankou _ _ = []

ymDaisangen _ (StandardShape _ ms _)
  | length [m | m <- ms, isTriOrKan m, isDragon (mTile m)] == 3 = [("daisangen", 1)]
ymDaisangen _ _ = []

ymSuushii _ (StandardShape p ms _) =
  let windTris = length [m | m <- ms, isTriOrKan m, isWind (mTile m)]
  in if windTris == 4 then [("daisuushii", 2)]
     else if windTris == 3 && isWind p then [("shousuushii", 1)]
     else []
ymSuushii _ _ = []

ymTsuuiisou ctx _ = [("tsuuiisou", 1) | all isHonor (scAllKinds ctx)]
ymChinroutou ctx _ = [("chinroutou", 1) | all isTerminal (scAllKinds ctx)]
ymRyuuiisou ctx _ = [("ryuuiisou", 1) | all isGreen (scAllKinds ctx)]

ymChuuren ctx (StandardShape _ _ _)
  | null (srMelds (scReq ctx))
  , all isSuit (scAllKinds ctx)
  , [s] <- nub (map kindSuit (scAllKinds ctx)) =
      let c = scConcealed ctx
          base = [3, 1, 1, 1, 1, 1, 1, 1, 3]
          cnts = [countsAt c (mkKind s r) | r <- [1 .. 9]]
      in if and (zipWith (>=) cnts base)
           then
             let wk = scWinKind ctx
                 r = kindRank wk
                 isPure = countsAt c wk == (if r == 1 || r == 9 then 4 else 2)
             in if isPure then [("junsei_chuuren", 2)] else [("chuuren", 1)]
           else []
ymChuuren _ _ = []

ymSuukantsu _ (StandardShape _ ms _)
  | length (filter ((== Kan) . mKind) ms) == 4 = [("suukantsu", 1)]
ymSuukantsu _ _ = []

-- =========================================================================
-- Declarative Standard Yaku Rules
-- =========================================================================

evalStandardYaku :: ScoreCtx -> HandShape -> [(String, Int)]
evalStandardYaku ctx shape = concatMap (\rule -> rule ctx shape) standardYakuRules

standardYakuRules :: [ScoreCtx -> HandShape -> [(String, Int)]]
standardYakuRules =
  [ ykSituational
  , ykTsumo
  , ykPinfu
  , ykTanyao
  , ykPeikou
  , ykYakuhai
  , ykChiitoi
  , ykToitoi
  , ykSanankou
  , ykSanshoku
  , ykSanshokuDoukou
  , ykIttsu
  , ykChantaJunchanHonroutou
  , ykShousangen
  , ykSankantsu
  , ykFlush
  ]

ykSituational :: ScoreCtx -> HandShape -> [(String, Int)]
ykSituational ctx _ =
  let fs = srFlags (scReq ctx)
      has f = Set.member f fs
  in [("double_riichi", 2) | has FlagDoubleRiichi]
     ++ [("riichi", 1)     | has FlagRiichi && not (has FlagDoubleRiichi)]
     ++ [("ippatsu", 1)    | has FlagIppatsu]
     ++ [("haitei", 1)     | has FlagHaitei]
     ++ [("houtei", 1)     | has FlagHoutei]
     ++ [("rinshan", 1)    | has FlagRinshan]
     ++ [("chankan", 1)    | has FlagChankan]

ykTsumo :: ScoreCtx -> HandShape -> [(String, Int)]
ykTsumo ctx _ =
  [("tsumo", 1) | scIsClosed ctx && srBy (scReq ctx) == Tsumo]

ykPinfu :: ScoreCtx -> HandShape -> [(String, Int)]
ykPinfu ctx (StandardShape p ms wt)
  | scIsClosed ctx
  , all ((== Seq) . mKind) ms
  , wt == Ryanmen
  , pairFu (srSeat (scReq ctx)) (srRound (scReq ctx)) p == 0 = [("pinfu", 1)]
ykPinfu _ _ = []

ykTanyao :: ScoreCtx -> HandShape -> [(String, Int)]
ykTanyao ctx _ = [("tanyao", 1) | all isSimple (scAllKinds ctx)]

ykPeikou :: ScoreCtx -> HandShape -> [(String, Int)]
ykPeikou ctx (StandardShape _ ms _)
  | scIsClosed ctx =
      let seqs = sort [mTile m | m <- ms, mKind m == Seq]
      in case seqs of
           [a, b, c, d] | a == b && c == d -> [("ryanpeikou", 3)]
           _ | hasAdjacentDup seqs         -> [("iipeikou", 1)]
             | otherwise                   -> []
ykPeikou _ _ = []

hasAdjacentDup :: Eq a => [a] -> Bool
hasAdjacentDup xs = any (uncurry (==)) (zip xs (drop 1 xs))

ykYakuhai :: ScoreCtx -> HandShape -> [(String, Int)]
ykYakuhai ctx (StandardShape _ ms _) =
  let tris = [mTile m | m <- ms, isTriOrKan m]
      req  = scReq ctx
  in [("yakuhai_haku",  1) | TileKind 31 `elem` tris]
     ++ [("yakuhai_hatsu", 1) | TileKind 32 `elem` tris]
     ++ [("yakuhai_chun",  1) | TileKind 33 `elem` tris]
     ++ [("yakuhai_seat",  1) | windKind (srSeat req) `elem` tris]
     ++ [("yakuhai_round", 1) | windKind (srRound req) `elem` tris]
ykYakuhai _ _ = []

ykChiitoi :: ScoreCtx -> HandShape -> [(String, Int)]
ykChiitoi _ (ChiitoiShape _) = [("chiitoi", 2)]
ykChiitoi _ _                = []

ykToitoi :: ScoreCtx -> HandShape -> [(String, Int)]
ykToitoi _ (StandardShape _ ms _)
  | all isTriOrKan ms = [("toitoi", 2)]
ykToitoi _ _ = []

ykSanankou :: ScoreCtx -> HandShape -> [(String, Int)]
ykSanankou _ (StandardShape _ ms _)
  | length (filter isClosedTriOrKan ms) == 3 = [("sanankou", 2)]
ykSanankou _ _ = []

ykSanshoku :: ScoreCtx -> HandShape -> [(String, Int)]
ykSanshoku ctx (StandardShape _ ms _) =
  let seqs = [mTile m | m <- ms, mKind m == Seq]
      hasAll r = all (\s -> mkKind s r `elem` seqs) [Man, Pin, Sou]
  in [("sanshoku", if scIsClosed ctx then 2 else 1) | any hasAll [1 .. 7]]
ykSanshoku _ _ = []

ykSanshokuDoukou :: ScoreCtx -> HandShape -> [(String, Int)]
ykSanshokuDoukou _ (StandardShape _ ms _) =
  let tris = [mTile m | m <- ms, isTriOrKan m]
      hasAll r = all (\s -> mkKind s r `elem` tris) [Man, Pin, Sou]
  in [("sanshoku_doukou", 2) | any hasAll [1 .. 9]]
ykSanshokuDoukou _ _ = []

ykIttsu :: ScoreCtx -> HandShape -> [(String, Int)]
ykIttsu ctx (StandardShape _ ms _) =
  let seqs = [mTile m | m <- ms, mKind m == Seq]
      hasSuit s = all (\r -> mkKind s r `elem` seqs) [1, 4, 7]
  in [("ittsu", if scIsClosed ctx then 2 else 1) | any hasSuit [Man, Pin, Sou]]
ykIttsu _ _ = []

ykChantaJunchanHonroutou :: ScoreCtx -> HandShape -> [(String, Int)]
ykChantaJunchanHonroutou ctx shape
  | all isYaochu (scAllKinds ctx) = [("honroutou", 2)]
  | StandardShape p ms _ <- shape
  , any ((== Seq) . mKind) ms
  , isYaochu p
  , all mentsuHasYaochu ms =
      if any isHonor (scAllKinds ctx)
        then [("chanta",  if scIsClosed ctx then 2 else 1)]
        else [("junchan", if scIsClosed ctx then 3 else 2)]
  | otherwise = []

mentsuHasYaochu :: Mentsu -> Bool
mentsuHasYaochu (Mentsu Seq k _) = kindRank k == 1 || kindRank k == 7
mentsuHasYaochu (Mentsu _   k _) = isYaochu k

ykShousangen :: ScoreCtx -> HandShape -> [(String, Int)]
ykShousangen _ (StandardShape p ms _)
  | isDragon p
  , length [m | m <- ms, isTriOrKan m, isDragon (mTile m)] == 2 = [("shousangen", 2)]
ykShousangen _ _ = []

ykSankantsu :: ScoreCtx -> HandShape -> [(String, Int)]
ykSankantsu _ (StandardShape _ ms _)
  | length (filter ((== Kan) . mKind) ms) == 3 = [("sankantsu", 2)]
ykSankantsu _ _ = []

ykFlush :: ScoreCtx -> HandShape -> [(String, Int)]
ykFlush ctx _ =
  let ks = scAllKinds ctx
      suits = nub [kindSuit k | k <- ks, isSuit k]
      hasHon = any isHonor ks
  in if length suits == 1
       then if hasHon
              then [("honitsu",  if scIsClosed ctx then 3 else 2)]
              else [("chinitsu", if scIsClosed ctx then 6 else 5)]
       else []

isTriOrKan :: Mentsu -> Bool
isTriOrKan m = mKind m == Triplet || mKind m == Kan

isClosedTriOrKan :: Mentsu -> Bool
isClosedTriOrKan m = isTriOrKan m && not (mOpen m)

-- =========================================================================
-- Fu and Payment Calculation
-- =========================================================================

pairFu :: Wind -> Wind -> TileKind -> Int
pairFu seat rnd k
  | isDragon k = 2
  | isWind k   = (if k == windKind seat then 2 else 0)
                 + (if k == windKind rnd then 2 else 0)
  | otherwise  = 0

mentsuFu :: Mentsu -> Int
mentsuFu (Mentsu Seq _ _) = 0
mentsuFu (Mentsu Triplet k open) =
  (if isYaochu k then 4 else 2) * (if open then 1 else 2)
mentsuFu (Mentsu Kan k open) =
  (if isYaochu k then 16 else 8) * (if open then 1 else 2)
mentsuFu (Mentsu Pair _ _) = 0

waitFu :: WaitType -> Int
waitFu Kanchan = 2
waitFu Penchan = 2
waitFu Tanki   = 2
waitFu Ryanmen = 0
waitFu Shanpon = 0

roundUp10 :: Int -> Int
roundUp10 x = ((x + 9) `div` 10) * 10

computeFu :: ScoreCtx -> HandShape -> Bool -> Int
computeFu _ (ChiitoiShape _) _ = 25
computeFu _ (KokushiShape _) _ = 20
computeFu ctx (StandardShape p ms wt) hasPinfu
  | hasPinfu && srBy req == Tsumo = 20
  | otherwise =
      let base = 20
          mRon = if scIsClosed ctx && srBy req == Ron then 10 else 0
          tsumoF = if srBy req == Tsumo then 2 else 0
          mFu = sum (map mentsuFu ms)
          pFu = pairFu (srSeat req) (srRound req) p
          wFu = waitFu wt
          raw = base + mRon + tsumoF + mFu + pFu + wFu
      in if not (scIsClosed ctx) && srBy req == Ron && raw == 20
           then 30
           else roundUp10 raw
  where
    req = scReq ctx

ordinaryBasic :: Int -> Int -> Int
ordinaryBasic han fu
  | han >= 13 = 8000
  | han >= 11 = 6000
  | han >= 8  = 4000
  | han >= 6  = 3000
  | han >= 5  = 2000
  | otherwise = min 2000 (fu * (1 `shiftL` (2 + han)))

ceil100 :: Int -> Int
ceil100 x = ((x + 99) `div` 100) * 100

computePayment :: ScoreRequest -> Int -> (String, Int)
computePayment req basic =
  let isDealer = srSeat req == East
      h = srHonba req
  in case srBy req of
       Ron ->
         let p = ceil100 ((if isDealer then 6 else 4) * basic) + 300 * h
         in ("ron:" ++ show p, p)
       Tsumo
         | isDealer ->
             let p = ceil100 (2 * basic) + 100 * h
             in ("all:" ++ show p, 3 * p)
         | otherwise ->
             let pNon = ceil100 basic + 100 * h
                 pDlr = ceil100 (2 * basic) + 100 * h
             in ("tsumo:" ++ show pNon ++ "/" ++ show pDlr, 2 * pNon + pDlr)

formatYakuList :: [(String, Int)] -> String
formatYakuList ys = intercalate "," [name ++ ":" ++ show v | (name, v) <- ys]

formatScoreResult :: ScoreResult -> String
formatScoreResult (ScoreError err) = "error=" ++ err
formatScoreResult (ScoreOrdinary ys han fu pay tot) =
  "yaku=" ++ formatYakuList ys
    ++ " han=" ++ show han
    ++ " fu=" ++ show fu
    ++ " pay=" ++ pay
    ++ " total=" ++ show tot
formatScoreResult (ScoreYakuman ys mult pay tot) =
  "yaku=" ++ formatYakuList ys
    ++ " yakuman=" ++ show mult
    ++ " pay=" ++ pay
    ++ " total=" ++ show tot
