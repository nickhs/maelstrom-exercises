module Handler where
import Lib (Context(Context, writeQueue), IncomingMessages(..), OutgoingMessages(..), meId, neighbours, serverMsgId, messages, getUUID, NeighbourState (NeighbourState, inflightMessage, messagesToSend))
import qualified Data.Map as Map
import qualified Data.Set as Set
import Control.Concurrent.STM (atomically, writeTQueue, newEmptyTMVarIO)
import Control.Concurrent.STM.TQueue (newTQueueIO)
import Control.Concurrent.Async (async, link)
import Data.Foldable (forM_)
import Control.Monad (forM)
import Init (InitPayload(InitPayload))
import Generate (GeneratePayload(GeneratePayload))
import Topology (TopologyPayload (TopologyPayload))
import Broadcast (BroadcastPayload (BroadcastPayload))
import Data.UUID ( toText )
import Messaging (nodeSender)
import Read (ReadPayload(ReadPayload))
import Data.Maybe (fromMaybe)
import qualified Data.Text as T

mkNeighbourState :: IO NeighbourState
mkNeighbourState = do
    inflightMessage <- newEmptyTMVarIO
    messagesToSend <- newTQueueIO
    pure NeighbourState {
        inflightMessage,
        messagesToSend
    }

handler :: Context -> T.Text -> IncomingMessages -> IO (Context, OutgoingMessages)
handler ctx _ (E payload) = pure (ctx, EchoOk payload)
handler ctx _ (Init (InitPayload nodeId _nodeIds)) = do
    let newCtx = ctx { meId = nodeId }
    pure (newCtx, InitOk)
handler ctx _ Generate = do
    uuid <- toText <$> getUUID ctx
    pure (ctx, GenerateOk $ GeneratePayload uuid)
handler ctx@(Context { serverMsgId, meId, writeQueue }) _ (Topology (TopologyPayload topo)) = do
    let myNeighbours = fromMaybe [] (Map.lookup meId topo)

    tqueues <- zip myNeighbours <$> mapM (const mkNeighbourState) [0..length myNeighbours]
    -- this is so bad but idc anymore FIXME
    _asyncHandles <- forM tqueues (\(toNodeId, tqueue) -> do
        thread <- async $ nodeSender (serverMsgId, meId, writeQueue) toNodeId tqueue
        link thread
        pure thread)

    let inited = Map.fromList tqueues
    pure (ctx { neighbours = inited }, TopologyOk)
handler ctx@(Context { neighbours, messages }) srcNode (Broadcast bp@(BroadcastPayload message)) = do
    if Set.member message messages
    -- if we've already seen the message then don't broadcast further
    then pure (ctx, BroadcastOk)
    -- otherwise add to our messages and tell all my neighbours!
    else do
        let newCtx = ctx { messages = Set.insert message messages }
        -- we need to write to each neighbour now to let them know!
        -- but only if this is the first time seeing this value
        -- FIXME except the neighbour we got this message from, they know obvi
        let toTell = map snd $ filter (\(nodeId, _) -> nodeId /= srcNode) $ Map.toList neighbours
        forM_ toTell (\(NeighbourState { messagesToSend }) -> 
            atomically (writeTQueue messagesToSend bp))
        -- and then we're done?
        pure (newCtx, BroadcastOk)
handler ctx@(Context { messages }) _ Read = pure (ctx, ReadOk $ ReadPayload $ Set.toList messages)