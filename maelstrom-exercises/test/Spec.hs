module Main where

import Test.HUnit (Test(TestCase, TestList), assertEqual, runTestTTAndExit)
import qualified Data.Aeson as JSON
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString as BS

import Messaging (payload, body, MsgEnvelope, MsgBodyReply)
import qualified Data.UUID as UUID
import Lib
    ( Context(Context, getUUID, serverMsgId, meId, neighbours, messages, writeQueue))
import Server (handleLine)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Control.Concurrent.STM (newTVarIO, newTQueueIO, readTQueue, atomically)
import Data.Knob (newKnob, newFileHandle, getContents)
import GHC.IO.IOMode (IOMode(WriteMode))

fakeUUID :: IO UUID.UUID
fakeUUID = pure UUID.nil

main :: IO ()
main = runTestTTAndExit tests
    where
        tests = TestList $ simpleTests ++ [topoTest , broadcastTest, fullTest]
        simpleTests = map (\x -> TestCase $ do
            _ <- parserTest x -- send to void instead?
            return ()) ["echo", "init", "generate"]

parserTestWithContext :: Context -> String -> IO Context
parserTestWithContext ctx name = do
    inp1 <- BSL.readFile ("test_resources/" <> name <> ".json")
    newCtx <- handleLine ctx inp1

    exp1 <- JSON.eitherDecode <$> BSL.readFile ("test_resources/" <> name <> "_ok.json")
    (expectedOut :: MsgEnvelope MsgBodyReply) <- case exp1 of
        Left err -> error err
        Right x -> pure x

    msg <- atomically $ readTQueue (writeQueue ctx)
    let myOut1 = (JSON.eitherDecode . BS.fromStrict) msg
    myOut <- case myOut1 of
        Left err -> error err
        Right x -> pure x

    assertEqual ("testParseHaskell_" <> name) expectedOut myOut

    let expectedOutJson = JSON.encode expectedOut
    let myOutJson = JSON.encode myOut
    assertEqual ("testParseJSON" <> name) expectedOutJson myOutJson
    pure newCtx

testContext :: IO Context
testContext = do
    msgId <- newTVarIO 0
    writeQueue <- newTQueueIO

    let ctx = Context {
        getUUID = fakeUUID,
        serverMsgId = msgId,
        meId = "n0",
        neighbours = Map.empty,
        messages = Set.empty,
        writeQueue = writeQueue
    }

    pure ctx

parserTest :: String -> IO Context
parserTest name = do
    ctx <- testContext
    parserTestWithContext ctx name

topoTest :: Test
topoTest = TestCase $ do
    newCtx <- parserTest "topology"
    assertEqual "neighbours" ["n2", "n3"] (Map.keys $ neighbours newCtx)

broadcastTest :: Test
broadcastTest = TestCase $ do
    newCtx <- parserTest "broadcast"
    assertEqual "broadcastMessages" (Set.fromList [1000]) (messages newCtx)

fullTest :: Test
fullTest = TestCase $ do
    initCtx <- parserTest "init"
    topoCtx <- parserTestWithContext initCtx "topology2"
    return ()