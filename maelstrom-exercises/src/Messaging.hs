module Messaging where
import qualified Data.Text as T
import GHC.Generics
import Data.Aeson
import Lib (OutgoingMessages, toPairs, messageTypeMapOut, ServerMessageId, NodeId, IncomingMessages (Broadcast), toPairs2, messageTypeMapOut2, NeighbourState (NeighbourState, inflightMessage))
import Control.Concurrent.STM (TQueue, atomically, readTQueue, readTVar, writeTVar, putTMVar, isEmptyTMVar, readTMVar, writeTQueue, unGetTQueue)
import Broadcast (BroadcastPayload)
import Debug.Trace (traceShowM)
import qualified Data.Aeson as JSON
import qualified Data.ByteString.Lazy.Char8 as BSL
import System.IO (hFlush, stdout)
import Control.Monad (when)
import Control.Concurrent (threadDelay)
import System.Timeout (timeout)
import Control.Applicative ((<|>))

data MsgEnvelope a = MsgEnvelope {
    src :: T.Text,
    dest :: T.Text,
    body :: a
} deriving (Show, Generic, Eq)

type MsgEnvelopeF = MsgEnvelope Msgs

data Msgs = MsgReq (MsgBody IncomingMessages) | MsgReply MsgBodyReply deriving (Show, Generic, Eq)
instance ToJSON Msgs
-- instance FromJSON Msgs

instance FromJSON Msgs where
    parseJSON jsonVal = do
        (wat :: MsgBodyReply) <- parseJSON jsonVal
        pure $ MsgReply wat


instance ToJSON a => ToJSON (MsgEnvelope a)
instance FromJSON a => FromJSON (MsgEnvelope a)

data MsgBody a = MsgBody {
    msgId :: Int,
    payload :: a
} deriving (Show, Eq)

instance FromJSON a => FromJSON (MsgBody a) where
    parseJSON jsonVal = withObject "MsgBody" (\o -> do
        msgId <- o .: "msg_id"
        parsed <- parseJSON jsonVal
        pure $ MsgBody msgId parsed) jsonVal

instance ToJSON (MsgBody IncomingMessages) where
    toJSON (MsgBody msgId payload) = object $
        toPairs2 payload <> [
            "type" .= messageTypeMapOut2 payload,
            "msg_id" .= msgId
        ]

data MsgBodyReply = MsgBodyReply {
    inReplyTo :: Int,
    replyPayload :: MsgBody OutgoingMessages
} deriving (Show, Eq)

instance ToJSON MsgBodyReply where
    toJSON (MsgBodyReply inReplyTo (MsgBody msgId payload)) = object $
        toPairs payload <> [
            "in_reply_to" .= inReplyTo,
            "type" .= messageTypeMapOut payload,
            "msg_id" .= msgId]

instance FromJSON MsgBodyReply where
    parseJSON jsonVal = withObject "MsgBodyReply" (\o -> do
        inReplyTo <- o .: "in_reply_to"
        parsed <- parseJSON jsonVal
        pure $ MsgBodyReply inReplyTo parsed) jsonVal

-- responsible for sending messages to other nodes in the cluster
-- and ensuring we get a response
-- a message on the workqueue is a message we need to send out
-- each work queue is scoped to a single neighbour (all messages are for one neighbour)
-- and a message type???
nodeSender :: (ServerMessageId, NodeId) -> NodeId -> NeighbourState -> IO ()
nodeSender (msgCounter, senderNodeId) toNodeId ns@(NeighbourState   workQueue inflightMessage) = do
    (payload, msgCount) <- atomically $ do
        hasInflight <- not <$> isEmptyTMVar inflightMessage
        when hasInflight (error "should not happen")
        msg <- readTQueue workQueue
        msgCount <- readTVar msgCounter
        writeTVar msgCounter (msgCount + 1)
        putTMVar inflightMessage msgCount
        pure (msg, msgCount)

    let req = MsgBody msgCount (Broadcast payload)
    let msg = MsgEnvelope senderNodeId toNodeId req
    putStrLn $ BSL.unpack $ JSON.encode msg
    hFlush stdout

    -- we only ever have one message in flight at a time
    resp <- timeout 5000 waitForResponse

    case resp of
        -- we sent the message successfully
        Just _ -> return ()
            -- traceShowM $ "sent message! " ++ show msg ++ " msgcount " ++ show msgCount

        -- we timed out waiting to send the message
        Nothing -> atomically (unGetTQueue workQueue payload) >> return ()

    -- and now try send another message
    nodeSender (msgCounter, senderNodeId) toNodeId ns
    where
        waitForResponse = atomically $ do
            -- we wait for the response handler to empty out the tmvar
            _ <- isEmptyTMVar inflightMessage
            return ()