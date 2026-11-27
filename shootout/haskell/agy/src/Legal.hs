module Legal
  ( FromSeat (..)
  , LegalEvent (..)
  , LegalRequest (..)
  , parseFromSeat
  , legalActions
  ) where

import Data.List (nub, sort)
import Data.Set (Set)
import qualified Data.Set as Set
import Agari
import Score
import Shanten
import Tile

data FromSeat = Kamicha | Toimen | Shimocha
  deriving (Eq, Ord, Show)

data LegalEvent
  = EvDraw !Tile
  | EvDiscard !Tile !FromSeat
  | EvCalled !Meld !Tile
  deriving (Eq, Show)

data LegalRequest = LegalRequest
  { lrHand    :: ![Tile]
  , lrMelds   :: ![Meld]
  , lrEvent   :: !LegalEvent
  , lrSeat    :: !Wind
  , lrRound   :: !Wind
  , lrFlags   :: !(Set Flag)
  , lrRiichi  :: !Bool
  , lrFuriten :: !Bool
  , lrWall    :: !Int
  , lrFirst   :: !Bool
  , lrKans    :: !Int
  } deriving (Eq, Show)

parseFromSeat :: String -> Maybe FromSeat
parseFromSeat "kamicha"  = Just Kamicha
parseFromSeat "toimen"   = Just Toimen
parseFromSeat "shimocha" = Just Shimocha
parseFromSeat _          = Nothing

kuikaeForbidden :: Meld -> TileKind -> [TileKind]
kuikaeForbidden (Meld Pon (t : _)) _ = [tileKind t]
kuikaeForbidden (Meld Chi ts) took =
  case sort (map tileKind ts) of
    [a, b, c]
      | took == b -> [b]
      | took == a -> a : [TileKind (unKind c + 1) | kindRank c < 9]
      | took == c -> c : [TileKind (unKind a - 1) | kindRank a > 1]
    _ -> [took]
kuikaeForbidden _ _ = []

removeOne :: Eq a => a -> [a] -> [a]
removeOne _ [] = []
removeOne x (y : ys)
  | x == y    = ys
  | otherwise = y : removeOne x ys

canWin :: LegalRequest -> Tile -> WinBy -> Bool
canWin req winTile winBy =
  let fs = if lrRiichi req
             then Set.insert FlagRiichi (lrFlags req)
             else lrFlags req
      sreq = ScoreRequest
        { srHand  = lrHand req
        , srMelds = lrMelds req
        , srWin   = winTile
        , srBy    = winBy
        , srSeat  = lrSeat req
        , srRound = lrRound req
        , srDora  = []
        , srUra   = []
        , srHonba = 0
        , srFlags = fs
        }
  in case scoreHand sreq of
       ScoreError _ -> False
       _            -> True

legalActions :: LegalRequest -> [String]
legalActions req = nub (sort rawActions)
  where
    rawActions = case lrEvent req of
      EvCalled meld took ->
        let forbid = kuikaeForbidden meld (tileKind took)
        in [ "discard:" ++ formatTile t
           | t <- nub (sort (lrHand req))
           , tileKind t `notElem` forbid
           ]

      EvDraw drawn ->
        let fullHand = drawn : lrHand req
            distinctTiles = nub (sort fullHand)
            fullCounts = countsFromTiles fullHand
            isClosed = not (any isOpenMeld (lrMelds req))

            discards
              | lrRiichi req = ["discard:" ++ formatTile drawn]
              | otherwise    = ["discard:" ++ formatTile t | t <- distinctTiles]

            tsumos = ["tsumo" | canWin req drawn Tsumo]

            riichis
              | not (lrRiichi req) && isClosed && lrWall req >= 4 =
                  [ "riichi:" ++ formatTile t
                  | t <- distinctTiles
                  , let h' = removeOne t fullHand
                        w = computeWaits h' (lrMelds req)
                  , wrShanten w == 0 && wrCount w > 0
                  ]
              | otherwise = []

            ankans
              | lrWall req >= 1 && lrKans req < 4 =
                  let quads = [k | k <- allKinds, countsAt fullCounts k == 4]
                  in if not (lrRiichi req)
                       then ["ankan:" ++ formatKind k | k <- quads]
                       else
                         let dk = tileKind drawn
                         in if dk `elem` quads
                              then
                                let beforeWaits = structuralWaits (countsFromTiles (lrHand req)) (length (lrMelds req))
                                    afterCounts = countsAdd dk (-4) fullCounts
                                    afterWaits  = structuralWaits afterCounts (length (lrMelds req) + 1)
                                in ["ankan:" ++ formatKind dk | beforeWaits == afterWaits]
                              else []
              | otherwise = []

            kakans
              | not (lrRiichi req) && lrWall req >= 1 && lrKans req < 4 =
                  let ponKinds = [tileKind t | Meld Pon (t : _) <- lrMelds req]
                  in [ "kakan:" ++ formatTile t
                     | t <- distinctTiles
                     , tileKind t `elem` ponKinds
                     ]
              | otherwise = []

            kyuushus
              | lrFirst req =
                  let yaochuPresent = length [k | k <- yaochuKinds, countsAt fullCounts k >= 1]
                  in ["kyuushu" | yaochuPresent >= 9]
              | otherwise = []

        in discards ++ tsumos ++ riichis ++ ankans ++ kakans ++ kyuushus

      EvDiscard disc fromSeat ->
        let isAnkanRob = Set.member FlagAnkanRob (lrFlags req)
            isChankan  = Set.member FlagChankan (lrFlags req)

            rons
              | lrFuriten req = []
              | isAnkanRob =
                  let c = countsFromTiles (disc : lrHand req)
                  in ["ron" | null (lrMelds req) && isKokushi c]
              | otherwise =
                  ["ron" | canWin req disc Ron]

            calls
              | isAnkanRob || isChankan || lrRiichi req || lrWall req < 1 = []
              | otherwise =
                  let dk = tileKind disc
                      sameTiles = sort [t | t <- lrHand req, tileKind t == dk]
                      hasRed = any tileRed sameTiles
                      plainCount = length (filter (not . tileRed) sameTiles)
                      pons =
                        [ "pon:" ++ formatTiles [Tile dk True, Tile dk False]
                        | hasRed && plainCount >= 1
                        ]
                        ++ [ "pon:" ++ formatTiles [Tile dk False, Tile dk False]
                           | plainCount >= 2
                           ]
                      kans =
                        [ "kan:" ++ formatKind dk
                        | lrKans req < 4 && length sameTiles == 3
                        ]
                      chis
                        | fromSeat == Kamicha && isSuit dk =
                            let s = kindSuit dk
                                r = kindRank dk
                                patterns = [(r - 2, r - 1), (r - 1, r + 1), (r + 1, r + 2)]
                            in [ "chi:" ++ formatTiles [t1, t2]
                               | (r1, r2) <- patterns
                               , r1 >= 1 && r2 <= 9
                               , t1 <- nub (sort [t | t <- lrHand req, tileKind t == mkKind s r1])
                               , t2 <- nub (sort [t | t <- lrHand req, tileKind t == mkKind s r2])
                               , let meld = Meld Chi (sort [disc, t1, t2])
                                     forbid = kuikaeForbidden meld dk
                                     remHand = removeOne t2 (removeOne t1 (lrHand req))
                               , any (\t -> tileKind t `notElem` forbid) remHand
                               ]
                        | otherwise = []
                  in pons ++ kans ++ chis

        in "pass" : rons ++ calls
