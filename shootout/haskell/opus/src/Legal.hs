-- | The @legal@ op. Winning and tenpai questions go to "Score" and "Hand";
-- only call enumeration and kuikae live here.
module Legal (From (..), Prompt (..), Table (..), legal) where

import Tile
import Meld
import Hand
import Score
import Data.Either (isRight)
import Data.List (delete, nub, sort, (\\))
import qualified Data.Set as S

data From = Kamicha | Toimen | Shimocha
  deriving (Eq, Show)

data Prompt
  = Draw Tile                -- ^ own turn, this tile just drawn
  | Discard Tile From        -- ^ another seat discarded (or is kanning) this tile
  | Called Meld Tile         -- ^ this seat just made the meld with this tile
  deriving (Eq, Show)

-- | The request: the seat's tiles, the prompt, and the table state.
data Table = Table
  { context :: Situation     -- ^ hand, melds, winds, dora, honba, flags
  , prompt :: Prompt
  , inRiichi :: Bool
  , furiten :: Bool
  , wall :: Int
  , firstTurn :: Bool
  , kansMade :: Int
  }

legal :: Table -> [String]
legal t = sort . nub $ case prompt t of
  Draw d -> ownTurn t d
  Discard d from -> response t d from
  Called m took -> afterCall t m took

-- | Does adding this tile complete the hand with a yaku?
wins :: Table -> Tile -> Bool -> Bool
wins t w tsumo = isRight (score s { winTile = w, byTsumo = tsumo, flags = fl })
  where
    s = context t
    fl = if inRiichi t then S.insert Riichi (flags s) else flags s

ownTurn :: Table -> Tile -> [String]
ownTurn t d = concat
  [ ["discard:" ++ showTile x | x <- if inRiichi t then [d] else full]
  , ["riichi:" ++ showTile x | closedHand ms, not (inRiichi t), wall t >= 4, x <- full, kind x `elem` tenpaiDiscards]
  , ["tsumo" | wins t d True]
  , ["ankan:" ++ showKind q | canKan, q <- nub fullKinds, countOf q fullKinds == 4, riichiKanOk q]
  , ["kakan:" ++ showTile x | canKan, not (inRiichi t), m <- ms, mtype m == Pon, x <- full, kind x == gbase (meldGroup m)]
  , ["kyuushu" | firstTurn t, length (nub (filter isYaochu fullKinds)) >= 9]
  ]
  where
    s = context t
    ms = melds s
    full = d : hand s
    fullKinds = map kind full
    canKan = wall t >= 1 && kansMade t < 4
    -- Riichi needs tenpai with a live wait after the discard.
    tenpaiDiscards =
      [ x | x <- nub fullKinds
      , let rest = delete x fullKinds
      , any ((> 0) . copiesLeft (rest ++ meldKinds ms)) (structuralWaits rest) ]
    -- In riichi: only the drawn kind, and the waits must not change.
    riichiKanOk q =
      not (inRiichi t)
        || (q == kind d && structuralWaits (map kind (hand s)) == structuralWaits (filter (/= q) fullKinds))

response :: Table -> Tile -> From -> [String]
response t d from = "pass" : ron ++ calls
  where
    s = context t
    h = hand s
    robbing = any (`S.member` flags s) [Chankan, AnkanRob]
    ron
      | furiten t = []
      -- Only kokushi may rob a closed kan.
      | AnkanRob `S.member` flags s = ["ron" | isKokushi (map kind (d : h))]
      | otherwise = ["ron" | wins t d False]
    calls
      | robbing || inRiichi t || wall t < 1 = []
      | otherwise = chi ++ pon ++ kan
    dk = kind d
    -- Every way to pick physical tiles of these kinds from the hand.
    picks [] _ = [[]]
    picks (q : qs) pool = [x : rest | x <- nub (filter ((== q) . kind) pool), rest <- picks qs (delete x pool)]
    -- A call is left out if every remaining tile would be a kuikae discard.
    leavesDiscard used = any ((`notElem` kuikae dk (map kind used)) . kind) (h \\ used)
    chi =
      [ "chi:" ++ showTiles used
      | from == Kamicha, not (isHonor dk)
      , (a, b) <- [(-2, -1), (-1, 1), (1, 2)]
      , num dk + a >= 1, num dk + b <= 9
      , used <- nub (map sort (picks [offset a dk, offset b dk] h))
      , leavesDiscard used ]
    pon =
      [ "pon:" ++ showTiles used
      | used <- nub (map sort (picks [dk, dk] h))
      , leavesDiscard used ]
    kan = ["kan:" ++ showKind dk | countOf dk (map kind h) >= 3, kansMade t < 4]

afterCall :: Table -> Meld -> Tile -> [String]
afterCall t m took =
  ["discard:" ++ showTile x | x <- hand (context t), kind x `notElem` kuikae (kind took) (map kind (delete took (mtiles m)))]

-- | Kuikae: the kinds that may not be discarded after calling this kind with
-- these tiles from hand. The called kind itself, and for a chi made with two
-- adjacent tiles the kind at their other end (if it exists).
kuikae :: Kind -> [Kind] -> [Kind]
kuikae called used = called : suji (sort used)
  where
    suji [a, b]
      | num b == num a + 1, num called < num a, num b + 1 <= 9 = [offset 1 b]
      | num b == num a + 1, num called > num b, num a - 1 >= 1 = [offset (-1) a]
    suji _ = []
