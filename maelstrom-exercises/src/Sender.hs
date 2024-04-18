module Sender where

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
import Lib (NeighbourState (NeighbourState), NodeId, ServerMessageId)
import System.Timeout (timeout)
import Messaging (MsgBodyReply(..), MsgBody(..), MsgEnvelope(..))


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
    -- let msg = BroadcastPayload $ Set.toList allMsgs
    let msg = undefined
    modifyTVar' msgCounter (+ 1)
    msgCount <- readTVar msgCounter
    putTMVar inflightMessage msgCount
    -- traceM $ "got msg id " ++ show msgCount
    -- let req = MsgBody msgCount (Broadcast msg)
    let req = undefined
    let out = MsgEnvelope senderNodeId toNodeId req
    -- let outRaw = toStrict $ JSON.encode out
    -- writeTQueue writeQueue outRaw
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

