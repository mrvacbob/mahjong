module Legal (Turn(..), Table(..), actions) where

import Data.List (delete, (\\))
import Shape
import Score
import Tiles

data Turn = Draw Tile | Discard Tile Bool | AfterCall Meld Tile

data Table = Table
    { inRiichi :: Bool
    , furiten :: Bool
    , wall :: Int
    , first :: Bool
    , kans :: Int
    }

actions :: Context -> Table -> [Tile] -> [Meld] -> Turn -> [String]
actions ctx table hand melds turn = unique $ case turn of
    Draw tile -> ownDraw tile
    Discard tile left -> opponentDiscard tile left
    AfterCall meld tile -> map (action "discard")
        (filter (allowedAfter (call meld) (map kind (meldTiles meld)) (kind tile)) hand)
  where
    active = inRiichi table
    canKan = wall table >= 1 && kans table < 4
    meldCount = length melds
    handKinds = map kind hand
    activeContext = if active then ctx {flags = "riichi" : flags ctx} else ctx
    hasFlag = flip elem (flags ctx)

    ownDraw tile =
        map (action "discard") discards
        ++ [action "riichi" t | not active, isClosed melds, wall table >= 4, t <- discards
                              , liveTenpai melds (map kind (delete t drawnHand))]
        ++ [ "tsumo" | canWin activeContext hand melds tile Tsumo ]
        ++ [ "kyuushu" | first table, length (filter outside (unique drawnKinds)) >= 9 ]
        ++ [ action "ankan" (plain k) | canKan, k <- unique drawnKinds, copies cs k == 4
            , not active || (k == kind tile && waitsBefore == structuralWaits (meldCount+1)
                                                          (filter (/=k) drawnKinds)) ]
        ++ [ action "kakan" t | canKan, not active, m <- melds, call m == Pon
                              , t <- discards, any ((== kind t) . kind) (meldTiles m) ]
      where
        drawnHand = tile : hand
        drawnKinds = map kind drawnHand
        cs = counts drawnKinds
        discards = if active then [tile] else unique drawnHand
        waitsBefore = structuralWaits meldCount handKinds

    opponentDiscard tile left =
        "pass" : ["ron" | not (furiten table), ron]
        ++ [ "pon:" ++ showTiles [a,b] | canCall, (a,b) <- pairs hand, bothMatch a b ]
        ++ [ action "kan" (plain k) | canCall, canKan, copies (counts handKinds) k == 3 ]
        ++ [ "chi:" ++ showTiles [a,b] | canCall, left, start <- sequenceStarts k
            , let run = [start..start+2]
            , [low,high] <- [delete k run]
            , a <- distinctHand, kind a == low, b <- distinctHand, kind b == high
            , any (allowedAfter Chi run k) (hand \\ [a,b]) ]
      where
        k = kind tile
        distinctHand = unique hand
        canCall = not (active || hasFlag "ankan_rob" || hasFlag "chankan") && wall table >= 1
        bothMatch a b = kind a == k && kind b == k
        ron
            | hasFlag "ankan_rob" = Orphans `elem` shapes meldCount (counts (k:handKinds))
            | otherwise = canWin activeContext hand melds tile Ron

action :: String -> Tile -> String
action name tile = name ++ ":" ++ showTile tile

pairs :: [a] -> [(a,a)]
pairs [] = []
pairs (t:ts) = [(t,u) | u <- ts] ++ pairs ts

allowedAfter :: Call -> [Kind] -> Kind -> Tile -> Bool
allowedAfter c run took tile = k /= took && k `notElem` otherEnd
  where
    k = kind tile
    otherEnd = case (c, delete took run) of
        (Chi, [a,b]) | b == a+1 -> filter ((==suit took) . suit) [if took < a then b+1 else a-1]
        _ -> []
