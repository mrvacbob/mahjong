module Main (main) where

import qualified Data.ByteString.Char8 as BS
import Data.List (intercalate)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Text.Read (readMaybe)
import Agari
import Legal
import Score
import Shanten
import Tile

main :: IO ()
main = do
  input <- BS.getContents
  let ls = BS.lines input
  mapM_ (BS.putStrLn . BS.pack . processLine . BS.unpack) ls

processLine :: String -> String
processLine line =
  case words line of
    [] -> ""
    (reqId : op : kvs) ->
      case parseKVs kvs of
        Left err -> reqId ++ " error=" ++ err
        Right kv ->
          case dispatch op kv of
            Left err -> reqId ++ " error=" ++ err
            Right res -> reqId ++ " " ++ res
    [reqId] -> reqId ++ " error=bad_request"

parseKVs :: [String] -> Either String (Map String String)
parseKVs = fmap Map.fromList . mapM parseOne
  where
    parseOne s = case break (== '=') s of
      (k, '=' : v) -> Right (k, v)
      _            -> Left "bad_kv"

reqKey :: Map String String -> String -> Either String String
reqKey m k = case Map.lookup k m of
  Just v  -> Right v
  Nothing -> Left ("missing_" ++ k)

optKey :: Map String String -> String -> String -> String
optKey m k def = Map.findWithDefault def k m

parseIntKey :: Map String String -> String -> Int -> Either String Int
parseIntKey m k def = case Map.lookup k m of
  Nothing -> Right def
  Just s  -> case readMaybe s of
    Just n  -> Right n
    Nothing -> Left ("bad_int_" ++ k)

parseBoolKey :: Map String String -> String -> Bool -> Either String Bool
parseBoolKey m k def = case Map.lookup k m of
  Nothing  -> Right def
  Just "0" -> Right False
  Just "1" -> Right True
  Just _   -> Left ("bad_bool_" ++ k)

parseWindKey :: Map String String -> String -> Wind -> Either String Wind
parseWindKey m k def = case Map.lookup k m of
  Nothing -> Right def
  Just s  -> case parseWind s of
    Just w  -> Right w
    Nothing -> Left ("bad_wind_" ++ k)

dispatch :: String -> Map String String -> Either String String
dispatch "agari"   kv = handleAgari kv
dispatch "shanten" kv = handleShanten kv
dispatch "waits"   kv = handleWaits kv
dispatch "score"   kv = handleScore kv
dispatch "legal"   kv = handleLegal kv
dispatch op        _  = Left ("unknown_op:" ++ op)

handleAgari :: Map String String -> Either String String
handleAgari kv = do
  hand  <- reqKey kv "hand" >>= parseTiles
  melds <- parseMelds (optKey kv "melds" "-")
  let forms = formatDecomps (decompose (countsFromTiles hand) (length melds))
  pure $ case forms of
    [] -> "win=0"
    _  -> "win=1 forms=" ++ intercalate ";" forms

handleShanten :: Map String String -> Either String String
handleShanten kv = do
  hand  <- reqKey kv "hand" >>= parseTiles
  melds <- parseMelds (optKey kv "melds" "-")
  let r = computeShanten (countsFromTiles hand) (length melds)
      fmtMaybe Nothing  = "x"
      fmtMaybe (Just n) = show n
  pure $ "std=" ++ show (shStd r)
      ++ " chiitoi=" ++ fmtMaybe (shChiitoi r)
      ++ " kokushi=" ++ fmtMaybe (shKokushi r)
      ++ " min=" ++ show (shMin r)

handleWaits :: Map String String -> Either String String
handleWaits kv = do
  hand  <- reqKey kv "hand" >>= parseTiles
  melds <- parseMelds (optKey kv "melds" "-")
  let r = computeWaits hand melds
  pure $ "shanten=" ++ show (wrShanten r)
      ++ " tiles=" ++ formatKinds (wrTiles r)
      ++ " count=" ++ show (wrCount r)

handleScore :: Map String String -> Either String String
handleScore kv = do
  hand  <- reqKey kv "hand" >>= parseTiles
  melds <- parseMelds (optKey kv "melds" "-")
  winT  <- reqKey kv "win" >>= parseTile
  byStr <- reqKey kv "by"
  winBy <- case byStr of
    "tsumo" -> Right Tsumo
    "ron"   -> Right Ron
    _       -> Left "bad_by"
  seat  <- parseWindKey kv "seat" East
  rnd   <- parseWindKey kv "round" East
  dora  <- parseTiles (optKey kv "dora" "-")
  ura   <- parseTiles (optKey kv "ura" "-")
  honba <- parseIntKey kv "honba" 0
  flags <- parseFlags (optKey kv "flags" "-")
  let req = ScoreRequest hand melds winT winBy seat rnd dora ura honba flags
  pure (formatScoreResult (scoreHand req))

handleLegal :: Map String String -> Either String String
handleLegal kv = do
  hand    <- reqKey kv "hand" >>= parseTiles
  melds   <- parseMelds (optKey kv "melds" "-")
  seat    <- parseWindKey kv "seat" East
  rnd     <- parseWindKey kv "round" East
  flags   <- parseFlags (optKey kv "flags" "-")
  riichi  <- parseBoolKey kv "riichi" False
  furiten <- parseBoolKey kv "furiten" False
  wall    <- parseIntKey kv "wall" 70
  first   <- parseBoolKey kv "first" False
  kans    <- parseIntKey kv "kans" 0
  ev      <- parseLegalEvent kv
  let req = LegalRequest hand melds ev seat rnd flags riichi furiten wall first kans
  pure ("actions=" ++ intercalate "," (legalActions req))

parseLegalEvent :: Map String String -> Either String LegalEvent
parseLegalEvent kv =
  case (Map.lookup "draw" kv, Map.lookup "discard" kv, Map.lookup "called" kv) of
    (Just d, Nothing, Nothing) -> EvDraw <$> parseTile d
    (Nothing, Just d, Nothing) -> do
      t <- parseTile d
      fromStr <- reqKey kv "from"
      fromSeat <- case parseFromSeat fromStr of
        Just fs -> Right fs
        Nothing -> Left "bad_from"
      Right (EvDiscard t fromSeat)
    (Nothing, Nothing, Just c) -> do
      m <- parseMeld c
      t <- reqKey kv "took" >>= parseTile
      Right (EvCalled m t)
    _ -> Left "bad_legal_event"
