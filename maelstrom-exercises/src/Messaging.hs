{-# OPTIONS_GHC -Wno-unused-imports #-}
module Messaging where
import qualified Data.Text as T
import GHC.Generics
import Data.Aeson
import Lib (OutgoingMessages, toPairs, messageTypeMapOut, ServerMessageId, NodeId, IncomingMessages (Broadcast), toPairs2, messageTypeMapOut2, NeighbourState (NeighbourState, inflightMessage))
import Control.Concurrent.STM (TQueue, atomically, readTQueue, readTVar, putTMVar, isEmptyTMVar, writeTQueue, unGetTQueue, retry, tryTakeTMVar, modifyTVar')
import qualified Data.Aeson as JSON
import Control.Monad (when)
import System.Timeout (timeout)
import Control.Applicative ((<|>))
import Data.ByteString
import Data.Functor ((<&>))

data MsgEnvelope a = MsgEnvelope {
    src :: T.Text,
    dest :: T.Text,
    body :: a
} deriving (Show, Generic, Eq)

type MsgEnvelopeF = MsgEnvelope Msgs

data Msgs = MsgReq (MsgBody IncomingMessages) | MsgReply MsgBodyReply deriving (Show, Generic, Eq)
instance ToJSON Msgs

instance FromJSON Msgs where
    parseJSON jsonVal = b <|> a
        where
            a = parseJSON jsonVal <&> MsgReq
            b = parseJSON jsonVal <&> MsgReply

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
nodeSender :: (ServerMessageId, NodeId, TQueue ByteString) -> NodeId -> NeighbourState -> IO ()
nodeSender (msgCounter, senderNodeId, writeQueue) toNodeId ns@(NeighbourState workQueue inflightMessage) = do
    (payload, msgCount, msg) <- atomically $ do
        -- precheck
        hasInflight <- not <$> isEmptyTMVar inflightMessage
        when hasInflight (error "should not happen")

        -- get a new msg to process
        msg <- readTQueue workQueue
        modifyTVar' msgCounter (+ 1)
        msgCount <- readTVar msgCounter
        putTMVar inflightMessage msgCount
        -- traceM $ "got msg id " ++ show msgCount
        let req = MsgBody msgCount (Broadcast msg)
        let out = MsgEnvelope senderNodeId toNodeId req
        let outRaw = toStrict $ JSON.encode out
        writeTQueue writeQueue outRaw
        pure (msg, msgCount, out)

    -- we only ever have one message in flight at a time
    resp <- timeout 1000000 waitForResponse

    case resp of
        -- we sent the message successfully
        Just _ -> do
            -- traceM $ "acked message! " ++ show msg ++ " msgcount " ++ show msgCount
            return ()

        -- we timed out waiting to send the message
        Nothing -> do
            -- traceShowM $ "timed out on ack for message " ++ show msg ++ " msgcount " ++ show msgCount
            atomically $ do
                unGetTQueue workQueue payload
                -- clear out the inflight message
                x <- tryTakeTMVar inflightMessage
                case x of
                    Nothing -> error "should not happen"
                    Just _ -> return ()


    -- and now try send another message
    nodeSender (msgCounter, senderNodeId, writeQueue) toNodeId ns
    where
        waitForResponse = atomically $ do
            -- we wait for the response handler to empty out the tmvar
            -- traceM "waiting on empty tvar"
            isEmpty <- isEmptyTMVar inflightMessage
            if isEmpty then return () else retry

{-
writeMessage :: TQueue a -> a -> STM ()
writeMessage writeQueue msg = do
    -- let out = JSON.encode msg
    BSL.hPut outHandle (out <> "\n")
    hFlush outHandle
    traceM $ "wrote response " <> show out
-}