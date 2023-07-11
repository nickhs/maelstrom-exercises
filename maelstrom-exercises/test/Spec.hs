module Main where

import Test.HUnit (Test(TestCase, TestList), assertEqual, runTestTTAndExit)
import qualified Data.Aeson as JSON
import qualified Data.ByteString.Lazy as BSL

import Data.UUID.V4 (nextRandom)
import qualified Data.UUID as UUID
import Lib (Context(Context, getUUID, serverMsgId, meId, neighbours), Messages (Incoming))
import Server (reply)
import Data.Aeson.Types (parse, parserThrowError)
import qualified Data.Set as Set
import Lib (Context(messages))
import qualified Data.Map as Map
import Control.Concurrent.STM (newTVarIO)
import Debug.Trace

fakeUUID :: IO UUID.UUID
fakeUUID = pure UUID.nil

main :: IO ()
main = runTestTTAndExit tests
    where 
        tests = TestList $ simpleTests ++ [{- topoTest ,-} broadcastTest, fullTest]
        simpleTests = map (\x -> TestCase $ do
            _ <- parserTest x -- send to void instead?
            return ()) ["echo", "init", "generate"]

parserTestWithContext :: Context -> String -> IO Context
parserTestWithContext ctx name = do
    inp1 <- JSON.eitherDecode <$> BSL.readFile ("test_resources/" <> name <> ".json")
    traceShowM inp1
    inp <- case inp1 of
        Left err -> error err
        Right msg -> pure msg

    (newCtx, myOut) <- reply ctx inp
    exp1 <- JSON.eitherDecode <$> BSL.readFile ("test_resources/" <> name <> "_ok.json")
    expectedOut <- case exp1 of
        Left err -> error err
        Right x -> pure x

    assertEqual ("testParseHaskell" <> name) expectedOut myOut

    let expectedOutJson = JSON.encode expectedOut
    let myOutJson = JSON.encode myOut
    assertEqual ("testParseJSON" <> name) expectedOutJson myOutJson
    pure newCtx

testContext :: IO Context
testContext = do
    msgId <- newTVarIO 0

    let ctx = Context {
        getUUID = fakeUUID,
        serverMsgId = msgId,
        meId = "n0",
        neighbours = Map.empty,
        messages = Set.empty
    }

    pure ctx

parserTest :: String -> IO Context
parserTest name = do
    ctx <- testContext
    parserTestWithContext ctx name

topoTest :: Test
topoTest = TestCase $ do
    newCtx <- parserTest "topology" 
    -- assertEqual "neighbours" ["n2", "n3"] (neighbours newCtx)
    assertEqual "neighbours" ["n1", "n2", "n3"] (Map.keys $ neighbours newCtx)

broadcastTest :: Test
broadcastTest = TestCase $ do
    newCtx <- parserTest "broadcast"
    assertEqual "broadcastMessages" (Set.fromList [1000]) (messages newCtx)

fullTest :: Test
fullTest = TestCase $ do
    initCtx <- parserTest "init"
    topoCtx <- parserTestWithContext initCtx "topology"
    return ()