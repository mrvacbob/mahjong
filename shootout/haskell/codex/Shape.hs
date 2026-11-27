module Shape where

import Data.List (sort)
import qualified Data.IntMap.Strict as Counts
import qualified Data.Set as Set
import Tiles

data GroupType = Pair | Sequence | Triplet deriving (Eq, Ord)
data Group = Group !Kind !GroupType deriving (Eq, Ord)

data Shape = Standard [Group] | SevenPairs | Orphans deriving (Eq)

type Counts = Counts.IntMap Int

counts :: [Kind] -> Counts
counts = foldl' (\acc k -> Counts.insertWith (+) k 1 acc) Counts.empty

copies :: Counts -> Kind -> Int
copies cs k = Counts.findWithDefault 0 k cs

groupKinds :: Group -> [Kind]
groupKinds (Group k Pair) = [k,k]
groupKinds (Group k Sequence) = [k,k+1,k+2]
groupKinds (Group k Triplet) = [k,k,k]

remove :: Counts -> [Kind] -> Counts
remove = foldl' (flip (Counts.update decrement))
  where
    decrement n = if n == 1 then Nothing else Just (n-1)

shapes :: Int -> Counts -> [Shape]
shapes meldCount cs =
    map Standard (standard (4-meldCount) True cs)
    ++ [SevenPairs | meldCount == 0, Counts.size cs == 7, all (==2) cs]
    ++ [Orphans | meldCount == 0, kokushiDistance cs == -1, all outside (Counts.keys cs)]
  where
    standard sets headNeeded tiles = case Counts.lookupMin tiles of
        Nothing -> [[] | sets == 0, not headNeeded]
        Just (k,n) -> concat
            [ takeGroup Pair sets False | headNeeded, n >= 2 ]
            ++ concat [ takeGroup Sequence (sets-1) headNeeded
                      | sets > 0, not (honor k), rank k <= 7
                      , Counts.member (k+1) tiles, Counts.member (k+2) tiles ]
            ++ concat [ takeGroup Triplet (sets-1) headNeeded | sets > 0, n >= 3 ]
          where
            takeGroup ty nextSets nextHead =
                let g = Group k ty
                in map (g:) (standard nextSets nextHead (remove tiles (groupKinds g)))

showShape :: Shape -> String
showShape (Standard gs) = join ',' (map (showTiles . map plain . groupKinds) (sort gs))
showShape SevenPairs = "chiitoi"
showShape Orphans = "kokushi"

unique :: Ord a => [a] -> [a]
unique = Set.toAscList . Set.fromList

kokushiDistance :: Counts -> Int
kokushiDistance cs = 13 - length present - fromEnum (any (>=2) present)
  where
    present = Counts.elems (Counts.filterWithKey (\k _ -> outside k) cs)

sevenPairsDistance :: Counts -> Int
sevenPairsDistance cs = 6 - length (filter (>=2) (Counts.elems cs)) + max 0 (7-Counts.size cs)

-- A profile records complete sets, partial sets and whether a head was used.
type Profile = (Int, Int, Int)

suitProfiles :: [Kind] -> [Profile]
suitProfiles = unique . search . counts
  where
    search cs = case Counts.lookupMin cs of
        Nothing -> [(0,0,0)]
        Just (k,n) ->
            search (remove cs [k])
            ++ [(s,t+1,h) | (s,t,h) <- pairRest]
            ++ [(s,t,1) | (s,t,0) <- pairRest]
            ++ [(s+1,t,h) | n >= 3, (s,t,h) <- search (remove cs [k,k,k])]
            ++ [(s+1,t,h) | suited, rank k <= 7
                          , has (k+1), has (k+2)
                          , (s,t,h) <- search (remove cs [k,k+1,k+2])]
            ++ [(s,t+1,h) | suited, next <- [k+1,k+2], suit next == suit k
                          , has next, (s,t,h) <- search (remove cs [k,next])]
          where
            suited = not (honor k)
            has = flip Counts.member cs
            pairRest = if n >= 2 then search (remove cs [k,k]) else []

suitTiles :: [Kind] -> [[Kind]]
suitTiles ks = [filter ((==s) . suit) ks | s <- [0..3]]

standardDistance :: Int -> [[Profile]] -> Int
standardDistance meldCount profiles = minimum
    [ 2*slots - 2*s - min t (slots-s) - h
    | (s,t,h) <- foldl' combine [(0,0,0)] (filter (/= [(0,0,0)]) profiles) ]
  where
    slots = 4 - meldCount
    combine left right = unique
        [(s+u,t+v,h+i) | (s,t,h) <- left, (u,v,i) <- right, s+u <= slots, h+i <= 1]

distances :: Int -> [Kind] -> (Int, Maybe Int, Maybe Int)
distances meldCount ks = (std, special sevenPairsDistance, special kokushiDistance)
  where
    std = standardDistance meldCount (map suitProfiles (suitTiles ks))
    special f = if meldCount == 0 then Just (f (counts ks)) else Nothing

minimumDistance :: (Int, Maybe Int, Maybe Int) -> Int
minimumDistance (std, pairs, orphans) = minimum (std : [n | Just n <- [pairs, orphans]])

structuralWaits :: Int -> [Kind] -> [Kind]
structuralWaits meldCount ks =
    [ k | k <- kinds
        , k `elem` nearby || (meldCount == 0 && outside k)
        , not (null (shapes meldCount (Counts.insertWith (+) k 1 cs))) ]
  where
    cs = counts ks
    nearby = concatMap (\k -> k : suitedNeighbors k) (Counts.keys cs)

availableWaits :: [Meld] -> [Kind] -> (Int, [(Kind, Int)])
availableWaits melds ks = (before, [(k, remaining k) | k <- improving, remaining k > 0])
  where
    meldCount = length melds
    cs = counts ks
    held = counts (ks ++ map kind (concatMap meldTiles melds))
    remaining k = 4 - copies held k
    partitions = suitTiles ks
    profiles = map suitProfiles partitions
    distance std tiles = minimumDistance
        (std, special sevenPairsDistance tiles, special kokushiDistance tiles)
    special f tiles = if meldCount == 0 then Just (f tiles) else Nothing
    before = distance (standardDistance meldCount profiles) cs
    improving
        | before == 0 = structuralWaits meldCount ks
        | otherwise =
            [ k | k <- kinds, remaining k > 0
                , let updated =
                          [ if s == suit k then suitProfiles (k : tiles) else profile
                          | (s, tiles, profile) <- zip3 [0..] partitions profiles ]
                      adjusted = standardDistance meldCount updated
                , distance adjusted (Counts.insertWith (+) k 1 cs) < before ]

liveTenpai :: [Meld] -> [Kind] -> Bool
liveTenpai melds ks = any ((<4) . copies held) (structuralWaits (length melds) ks)
  where
    held = counts (ks ++ map kind (concatMap meldTiles melds))
