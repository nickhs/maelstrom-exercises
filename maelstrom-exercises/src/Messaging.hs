module Messaging where

import Broadcast (BroadcastPayload (..))
import Control.Applicative ((<|>))
import Control.Concurrent.STM (TQueue, atomically, flushTQueue, isEmptyTMVar, modifyTVar', putTMVar, readTVar, retry, tryTakeTMVar, unGetTQueue, writeTQueue)
import Control.Monad (unless, when)
import Data.Aeson
import qualified Data.Aeson as JSON
import Data.Aeson.Types (Parser)
import Data.ByteString (ByteString, toStrict)
import Data.Foldable (foldl')
import Data.Reflection (Reifies)
import qualified Data.Set as Set
import Data.Tagged (Tagged (Tagged), unTagged)
import qualified Data.Text as T
import GHC.Generics
import Lib (IncomingMessages (Broadcast), MessageTypeMaps, NeighbourState (NeighbourState), NodeId, OutgoingMessages, ServerMessageId, messageTypeMapOut, messageTypeMapOut2, toPairs, toPairs2)
import System.Timeout (timeout)

data MsgEnvelope a = MsgEnvelope
  { src :: T.Text,
    dest :: T.Text,
    body :: a
  }
  deriving (Show, Generic, Eq)

instance (ToJSON a) => ToJSON (MsgEnvelope a)
instance (FromJSON a) => FromJSON (MsgEnvelope a)

data Msgs = MsgReq (MsgBody IncomingMessages) | MsgReply MsgBodyReply deriving (Show, Generic, Eq)
instance ToJSON Msgs

instance {-# OVERLAPPING #-} (Reifies m (MessageTypeMaps)) => FromJSON (Tagged m Msgs) where
  parseJSON jsonVal = a <|> b
    where
      a :: Parser (Tagged m Msgs) = do
        (x :: MsgBody (Tagged m IncomingMessages)) <- parseJSON jsonVal
        let f = unTagged $ payload x
        let q = MsgReq $ x {payload = f}
        pure $ Tagged q
      b :: Parser (Tagged m Msgs) = do
        (x :: Tagged m MsgBodyReply) <- parseJSON jsonVal
        pure $ Tagged (MsgReply (unTagged x))

data MsgBody a = MsgBody
  { msgId :: Int,
    payload :: a
  }
  deriving (Show, Eq)

instance (FromJSON a) => FromJSON (MsgBody a) where
  parseJSON jsonVal =
    withObject
      "MsgBody"
      ( \o -> do
          msgId <- o .: "msg_id"
          (parsed :: a) <- parseJSON jsonVal
          pure $ MsgBody msgId parsed
      )
      jsonVal

instance ToJSON (MsgBody IncomingMessages) where
  toJSON (MsgBody msgId payload) =
    object $
      toPairs2 payload
        <> [ "type" .= messageTypeMapOut2 payload,
             "msg_id" .= msgId
           ]

data MsgBodyReply = MsgBodyReply
  { inReplyTo :: Int,
    replyPayload :: MsgBody OutgoingMessages
  }
  deriving (Show, Eq)

instance ToJSON MsgBodyReply where
  toJSON (MsgBodyReply inReplyTo (MsgBody msgId payload)) =
    object $
      toPairs payload
        <> [ "in_reply_to" .= inReplyTo,
             "type" .= messageTypeMapOut payload,
             "msg_id" .= msgId
           ]

instance {-# OVERLAPPING #-} (Reifies m MessageTypeMaps) => FromJSON (Tagged m MsgBodyReply) where
  parseJSON jsonVal =
    withObject
      "MsgBodyReply"
      ( \o -> do
          inReplyTo <- o .: "in_reply_to"
          (parsed :: MsgBody (Tagged m OutgoingMessages)) <- parseJSON jsonVal
          let fixed = parsed {payload = unTagged (payload parsed)}
          pure $ Tagged $ MsgBodyReply inReplyTo fixed
      )
      jsonVal

-- responsible for sending messages to other nodes in the cluster
-- and ensuring we get a response
-- a message on the workqueue is a message we need to send out
-- each work queue is scoped to a single neighbour (all messages are for one neighbour)
-- and a message type???
nodeSender :: (ServerMessageId, NodeId, TQueue ByteString) -> NodeId -> NeighbourState -> IO ()
nodeSender (msgCounter, senderNodeId, writeQueue) toNodeId ns@(NeighbourState workQueue inflightMessage) = do
  (payload, _msgCount, _msg) <- atomically $ do
    -- precheck
    hasInflight <- not <$> isEmptyTMVar inflightMessage
    when hasInflight (error "should not happen")

    -- get a new msg to process
    msgs <- flushTQueue workQueue
    let allMsgs = foldl' Set.union Set.empty msgs
    let msg = BroadcastPayload $ Set.toList allMsgs
    modifyTVar' msgCounter (+ 1)
    msgCount <- readTVar msgCounter
    putTMVar inflightMessage msgCount
    -- traceM $ "got msg id " ++ show msgCount
    let req = MsgBody msgCount (Broadcast msg)
    let out = MsgEnvelope senderNodeId toNodeId req
    let outRaw = toStrict $ JSON.encode out
    writeTQueue writeQueue outRaw
    pure (allMsgs, msgCount, out)

  -- we only ever have one message in flight at a time
  resp <- timeout 2000000 waitForResponse

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
      unless isEmpty retry