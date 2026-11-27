module Main (main) where

import Control.Monad (guard)
import Data.Char (isSpace)
import Data.List (elemIndex)
import Data.Maybe (fromMaybe)
import System.IO (BufferMode(LineBuffering), hSetBuffering, stdout)
import Text.Read (readMaybe)
import qualified Data.Map.Strict as Map
import Legal
import Score
import Shape
import Tiles

type Fields = Map.Map String String

field :: String -> String -> Fields -> String
field = Map.findWithDefault

parseField :: String -> Maybe (String, String)
parseField word = case break (=='=') word of
    (key, '=':value) | not (null key) && not (null value) -> Just (key,value)
    _ -> Nothing

parseContext :: Fields -> Maybe Context
parseContext f =
    Context <$> wind (field "E" "seat" f) <*> wind (field "E" "round" f)
        <*> parseTiles (field "-" "dora" f) <*> parseTiles (field "-" "ura" f)
        <*> readMaybe (field "0" "honba" f) <*> pure (split ',' (field "-" "flags" f))
  where
    wind [w] = (+27) <$> elemIndex w "ESWN"
    wind _ = Nothing

parseTable :: Fields -> Maybe Table
parseTable f =
    Table <$> toggle "riichi" <*> toggle "furiten" <*> number "70" "wall"
        <*> toggle "first" <*> number "0" "kans"
  where
    toggle key = lookup (field "0" key f) [("0",False),("1",True)]
    number def key = readMaybe (field def key f)

parseTurn :: Fields -> Maybe Turn
parseTurn f = case map (flip Map.lookup f) ["draw","discard","called"] of
    [Just tile, Nothing, Nothing] -> Draw <$> parseTile tile
    [Nothing, Just tile, Nothing] ->
        Discard <$> parseTile tile <*> pure (Map.lookup "from" f == Just "kamicha")
    [Nothing, Nothing, Just meld] ->
        AfterCall <$> parseMeld meld <*> (Map.lookup "took" f >>= parseTile)
    _ -> Nothing

respond :: String -> Fields -> Maybe String
respond op f = do
    hand <- Map.lookup "hand" f >>= parseTiles
    melds <- parseMelds (field "-" "melds" f)
    let n = length melds
        ks = map kind hand
        short = length hand == 13 - 3*n
        full = length hand == 14 - 3*n
    guard (n <= 4)
    case op of
        "agari" -> do
            guard full
            pure $ case unique (map showShape (shapes n (counts ks))) of
                [] -> "win=0"
                forms -> "win=1 forms=" ++ join ';' forms
        "shanten" -> do
            guard (short || full)
            let ds@(std,pairs,orphans) = distances n ks
                special = maybe "x" show
            pure ("std=" ++ show std ++ " chiitoi=" ++ special pairs
                  ++ " kokushi=" ++ special orphans ++ " min=" ++ show (minimumDistance ds))
        "waits" -> do
            guard short
            let (distance,draws) = availableWaits melds ks
            pure ("shanten=" ++ show distance ++ " tiles=" ++ showTiles (map (plain . fst) draws)
                  ++ " count=" ++ show (sum (map snd draws)))
        "score" -> do
            guard short
            ctx <- parseContext f
            tile <- Map.lookup "win" f >>= parseTile
            how <- Map.lookup "by" f >>= flip lookup [("ron",Ron),("tsumo",Tsumo)]
            pure (score ctx hand melds tile how)
        "legal" -> do
            ctx <- parseContext f
            table <- parseTable f
            turn <- parseTurn f
            guard $ case turn of
                AfterCall _ _ -> full
                _ -> short
            let options = actions ctx table hand melds turn
            guard (not (null options))
            pure ("actions=" ++ join ',' options)
        _ -> Nothing

runLine :: String -> String
runLine str = case words str of
    ident:op:fields ->
        ident ++ " " ++ fromMaybe "error=bad_input"
            (traverse parseField fields >>= respond op . Map.fromList)
    _ -> takeWhile (not . isSpace) str ++ " error=bad_input"

main :: IO ()
main = do
    hSetBuffering stdout LineBuffering
    interact (unlines . map runLine . lines)
