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
    fl = S.delete AnkanRob (flags s) `S.union` (if inRiichi t then S.singleton Riichi else S.empty)

ownTurn :: Table -> Tile -> [String]
ownTurn t d = concat
  [ ["discard:" ++ showTile x | x <- if inRiichi t then [d] else full]
  , ["riichi:" ++ showTile x | closed, not (inRiichi t), wall t >= 4, x <- nub full, tenpaiAfter x]
  , ["tsumo" | wins t d True]
  , ["ankan:" ++ showKind q | canKan, q <- nub (map kind full), countOf q (map kind full) == 4, riichiKanOk q]
  , ["kakan:" ++ showTile x | canKan, not (inRiichi t), m <- ms, mtype m == Pon, x <- full, kind x == ponKind m]
  , ["kyuushu" | firstTurn t, length (nub (filter isYaochu (map kind full))) >= 9]
  ]
  where
    s = context t
    ms = melds s
    k = length ms
    full = d : hand s
    closed = not (any isOpenMeld ms)
    meldKinds = concatMap (map kind . mtiles) ms
    canKan = wall t >= 1 && kansMade t < 4
    ponKind = kind . head' . mtiles
    -- Riichi needs tenpai with a live wait after the discard.
    tenpaiAfter x =
      let rest = map kind (delete x full)
          (sh, _, n) = liveWaits k rest (rest ++ meldKinds)
       in sh == 0 && n > 0
    -- In riichi: only the drawn kind, and the waits must not change.
    riichiKanOk q
      | not (inRiichi t) = True
      | otherwise =
          q == kind d
            && improving k (map kind (hand s))
                 == improving (k + 1) (filter (/= q) (map kind full))

response :: Table -> Tile -> From -> [String]
response t d from = "pass" : ron ++ calls
  where
    s = context t
    h = hand s
    robbing = any (`S.member` flags s) [Chankan, AnkanRob]
    ron
      | furiten t = []
      | AnkanRob `S.member` flags s = ["ron" | null (melds s), isKokushi (map kind (d : h))]
      | otherwise = ["ron" | wins t d False]
    calls
      | robbing || inRiichi t || wall t < 1 = []
      | otherwise = chi ++ pon ++ kan
    dk = kind d
    -- Every way to pick physical tiles of these kinds from the hand.
    picks [] _ = [[]]
    picks (q : qs) pool = [x : rest | x <- nub (filter ((== q) . kind) pool), rest <- picks qs (delete x pool)]
    allowed forbidden used = any ((`notElem` forbidden) . kind) (h \\ used)
    chi =
      [ "chi:" ++ showTiles used
      | from == Kamicha, not (isHonor dk)
      , (a, b) <- [(-2, -1), (-1, 1), (1, 2)]
      , num dk + a >= 1, num dk + b <= 9
      , used <- nub (map sort (picks [dk { num = num dk + a }, dk { num = num dk + b }] h))
      , allowed (dk : suji dk (map kind used)) used ]
    pon =
      [ "pon:" ++ showTiles used
      | used <- nub (map sort (picks [dk, dk] h))
      , allowed [dk] used ]
    kan = ["kan:" ++ showKind dk | countOf dk (map kind h) >= 3, kansMade t < 4]

afterCall :: Table -> Meld -> Tile -> [String]
afterCall t m took = ["discard:" ++ showTile x | x <- hand (context t), kind x `notElem` forbidden]
  where
    tk = kind took
    forbidden = case mtype m of
      Chi -> tk : suji tk (sort (map kind (delete took (mtiles m))))
      _ -> [tk]

-- | Kuikae beyond the called kind: when the two tiles from hand are adjacent,
-- the kind at their other end (if it exists).
suji :: Kind -> [Kind] -> [Kind]
suji called [a, b]
  | num b == num a + 1, num called < num a, num b + 1 <= 9 = [b { num = num b + 1 }]
  | num b == num a + 1, num called > num b, num a - 1 >= 1 = [a { num = num a - 1 }]
suji _ _ = []

head' :: [a] -> a
head' (x : _) = x
head' [] = error "empty meld"
