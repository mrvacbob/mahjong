-- | Line protocol: @<id> <op> key=value ...@ in, @<id> key=value ...@ out.
module Main (main) where

import Tile
import Meld
import Hand
import Score
import Legal
import Control.Exception (SomeException, evaluate, try)
import Control.Monad (mfilter)
import Data.List (intercalate, nub, sort)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import System.IO
import Text.Read (readMaybe)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  mapM_ (\l -> respond l >>= putStrLn) . filter (not . null) . lines =<< getContents

-- | Answer one line; a bad request or an internal failure becomes @error=@.
respond :: String -> IO String
respond line = case words line of
  rid : op : args -> do
    r <- try @SomeException (evaluate (forceString (answer op (M.fromList (map keyValue args)))))
    pure $ rid ++ " " ++ case r of
      Left _ -> "error=internal"
      Right (Left why) -> "error=" ++ why
      Right (Right out) -> out
  rid : _ -> pure (rid ++ " error=bad_request")
  [] -> pure "error=bad_request"
  where
    keyValue a = case break (== '=') a of
      (k, _ : v) -> (k, v)
      (k, []) -> (k, "")
    forceString e = either length length e `seq` e

type Args = M.Map String String

answer :: String -> Args -> Either String String
answer op a = case op of
  "agari" -> showAgari <$> kindsArg "hand" a <* meldsArg a
  "shanten" -> showShanten <$> kindsArg "hand" a <*> meldsArg a
  "waits" -> showWaits <$> kindsArg "hand" a <*> meldsArg a
  "score" -> showScore . score <$> (situation a =<< tileArg "win" a)
  "legal" -> ("actions=" ++) . intercalate "," . legal <$> table a
  _ -> Left "unknown_op"

------------------------------------------------------------------------------
-- Argument parsing

arg :: String -> String -> Args -> String
arg k def = M.findWithDefault def k

parsed :: String -> (String -> Maybe b) -> String -> Args -> Either String b
parsed k p def a = maybe (Left ("bad_" ++ k)) Right (p (arg k def a))

tilesArg :: String -> Args -> Either String [Tile]
tilesArg k = parsed k parseTiles "-"

kindsArg :: String -> Args -> Either String [Kind]
kindsArg k a = map kind <$> tilesArg k a

tileArg :: String -> Args -> Either String Tile
tileArg k = parsed k parseTile ""

meldsArg :: Args -> Either String [Meld]
meldsArg = parsed "melds" parseMelds "-"

windArg :: String -> Args -> Either String Kind
windArg k = parsed k (`lookup` [(w, Kind Honor n) | (w, n) <- zip ["E", "S", "W", "N"] [1 ..]]) "E"

-- | A count: a non-negative integer.
intArg :: (Read n, Show n, Ord n, Num n) => String -> n -> Args -> Either String n
intArg k def = parsed k (mfilter (>= 0) . readMaybe) (show def)

boolArg :: String -> Args -> Either String Bool
boolArg k = parsed k (`lookup` [("0", False), ("1", True)]) "0"

flagsArg :: Args -> Either String (S.Set Flag)
flagsArg a = case arg "flags" "-" a of
  "-" -> Right S.empty
  fs -> maybe (Left "bad_flags") (Right . S.fromList) (traverse parseFlag (splitOn ',' fs))

-- | Context keys shared by @score@ and @legal@, around the tile being won on.
situation :: Args -> Tile -> Either String Situation
situation a w = do
  h <- tilesArg "hand" a
  ms <- meldsArg a
  seat <- windArg "seat" a
  rnd <- windArg "round" a
  dora <- tilesArg "dora" a
  ura <- tilesArg "ura" a
  hb <- intArg "honba" 0 a
  fl <- flagsArg a
  by <- case arg "by" "ron" a of
    "ron" -> Right False
    "tsumo" -> Right True
    _ -> Left "bad_by"
  pure Situation
    { hand = h, melds = ms, winTile = w, byTsumo = by, seatWind = seat, roundWind = rnd
    , doraInd = dora, uraInd = ura, honba = hb, flags = fl }

table :: Args -> Either String Table
table a = do
  p <- case filter (`M.member` a) ["draw", "discard", "called"] of
    ["draw"] -> Draw <$> tileArg "draw" a
    ["discard"] -> Discard <$> tileArg "discard" a <*> parsed "from" (`lookup` froms) "" a
    ["called"] -> Called <$> parsed "called" parseMeld "" a <*> tileArg "took" a
    [] -> Left "no_prompt"
    _ -> Left "bad_prompt"            -- exactly one trigger per request
  -- Legal tries this tile (or each candidate) as the win itself.
  s <- situation a $ case p of
    Draw d -> d
    Discard d _ -> d
    Called _ took -> took
  r <- boolArg "riichi" a
  f <- boolArg "furiten" a
  w <- intArg "wall" 70 a
  fst' <- boolArg "first" a
  k <- intArg "kans" 0 a
  pure Table { context = s, prompt = p, inRiichi = r, furiten = f, wall = w, firstTurn = fst', kansMade = k }
  where froms = [("kamicha", Kamicha), ("toimen", Toimen), ("shimocha", Shimocha)]

------------------------------------------------------------------------------
-- The shape ops

-- | Melds are validated but play no part: forms list the concealed tiles only.
showAgari :: [Kind] -> String
showAgari ks
  | null forms = "win=0"
  | otherwise = "win=1 forms=" ++ intercalate ";" forms
  where
    forms = nub . sort $
      [intercalate "," (map showGroup gs) | gs <- decompose ks]
        ++ ["chiitoi" | isChiitoi ks]
        ++ ["kokushi" | isKokushi ks]

showShanten :: [Kind] -> [Meld] -> String
showShanten ks ms = unwords
  [ "std=" ++ show (stdShanten sh)
  , "chiitoi=" ++ special (chiitoiShanten sh)
  , "kokushi=" ++ special (kokushiShanten sh)
  , "min=" ++ show (minShanten sh) ]
  where
    sh = shanten (length ms) ks
    special = maybe "x" show

showWaits :: [Kind] -> [Meld] -> String
showWaits ks ms = unwords ["shanten=" ++ show sh, "tiles=" ++ showKinds live, "count=" ++ show n]
  where (sh, live, n) = liveWaits (length ms) ks (ks ++ meldKinds ms)
