-- | Line protocol: @<id> <op> key=value ...@ in, @<id> key=value ...@ out.
module Main (main) where

import Tile
import Meld
import Hand
import Score
import Legal
import Control.Exception (SomeException, evaluate, try)
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
    r <- try (evaluate (forceString (answer op (M.fromList (map keyValue args)))))
    pure $ rid ++ " " ++ case r of
      Left e -> "error=internal" ++ const "" (e :: SomeException)
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
  "agari" -> agari <$> tilesArg "hand" a <*> meldsArg a
  "shanten" -> shanten <$> tilesArg "hand" a <*> meldsArg a
  "waits" -> waits <$> tilesArg "hand" a <*> meldsArg a
  "score" | M.notMember "win" a -> Left "bad_win"
          | otherwise -> showScore . score <$> situation a
  "legal" -> unwords . pure . ("actions=" ++) . intercalate "," . legal <$> table a
  _ -> Left "unknown_op"

------------------------------------------------------------------------------
-- Argument parsing

arg :: String -> String -> Args -> String
arg k def = M.findWithDefault def k

parsed :: String -> (String -> Maybe b) -> String -> Args -> Either String b
parsed k p def a = maybe (Left ("bad_" ++ k)) Right (p (arg k def a))

tilesArg :: String -> Args -> Either String [Tile]
tilesArg k = parsed k parseTiles "-"

tileArg :: String -> Args -> Either String Tile
tileArg k = parsed k parseTile ""

meldsArg :: Args -> Either String [Meld]
meldsArg = parsed "melds" parseMelds "-"

windArg :: String -> Args -> Either String Kind
windArg k = parsed k (`lookup` [(w, Kind Honor n) | (w, n) <- zip ["E", "S", "W", "N"] [1 ..]]) "E"

intArg :: String -> Int -> Args -> Either String Int
intArg k def = parsed k readMaybe (show def)

boolArg :: String -> Args -> Either String Bool
boolArg k a = (/= 0) <$> intArg k 0 a

flagsArg :: Args -> Either String (S.Set Flag)
flagsArg a = case arg "flags" "-" a of
  "-" -> Right S.empty
  fs -> maybe (Left "bad_flags") (Right . S.fromList) (traverse parseFlag (splitComma fs))
  where
    splitComma s = case break (== ',') s of
      (x, []) -> [x]
      (x, _ : rest) -> x : splitComma rest

-- | Context keys shared by @score@ and @legal@.
situation :: Args -> Either String Situation
situation a = do
  h <- tilesArg "hand" a
  ms <- meldsArg a
  seat <- windArg "seat" a
  rnd <- windArg "round" a
  dora <- tilesArg "dora" a
  ura <- tilesArg "ura" a
  hb <- intArg "honba" 0 a
  fl <- flagsArg a
  w <- if M.member "win" a then tileArg "win" a else Right (winTile defaultSituation)
  by <- case arg "by" "ron" a of
    "ron" -> Right False
    "tsumo" -> Right True
    _ -> Left "bad_by"
  pure Situation
    { hand = h, melds = ms, winTile = w, byTsumo = by, seatWind = seat, roundWind = rnd
    , doraInd = dora, uraInd = ura, honba = hb, flags = fl }

table :: Args -> Either String Table
table a = do
  s <- situation a
  p <- case (M.lookup "draw" a, M.lookup "discard" a, M.lookup "called" a) of
    (Just _, _, _) -> Draw <$> tileArg "draw" a
    (_, Just _, _) -> Discard <$> tileArg "discard" a <*> parsed "from" (`lookup` froms) "" a
    (_, _, Just c) -> Called <$> maybe (Left "bad_called") Right (parseMeld c) <*> tileArg "took" a
    _ -> Left "no_prompt"
  r <- boolArg "riichi" a
  f <- boolArg "furiten" a
  w <- intArg "wall" 70 a
  fst' <- boolArg "first" a
  k <- intArg "kans" 0 a
  pure Table { context = s, prompt = p, inRiichi = r, furiten = f, wall = w, firstTurn = fst', kansMade = k }
  where froms = [("kamicha", Kamicha), ("toimen", Toimen), ("shimocha", Shimocha)]

------------------------------------------------------------------------------
-- The shape ops

agari :: [Tile] -> [Meld] -> String
agari h ms
  | null forms = "win=0"
  | otherwise = "win=1 forms=" ++ intercalate ";" forms
  where
    ks = map kind h
    closed = null ms
    forms = nub . sort $
      [intercalate "," (map showGroup gs) | gs <- decompose ks]
        ++ ["chiitoi" | closed, isChiitoi ks]
        ++ ["kokushi" | closed, isKokushi ks]

shanten :: [Tile] -> [Meld] -> String
shanten h ms = unwords
  [ "std=" ++ show st
  , "chiitoi=" ++ special shantenChiitoi
  , "kokushi=" ++ special shantenKokushi
  , "min=" ++ show (shantenMin (length ms) ks) ]
  where
    ks = map kind h
    st = shantenStd (length ms) ks
    special f = if null ms then show (f ks) else "x"

waits :: [Tile] -> [Meld] -> String
waits h ms = unwords ["shanten=" ++ show sh, "tiles=" ++ showKinds live, "count=" ++ show n]
  where
    ks = map kind h
    (sh, live, n) = liveWaits (length ms) ks (ks ++ concatMap (map kind . mtiles) ms)
