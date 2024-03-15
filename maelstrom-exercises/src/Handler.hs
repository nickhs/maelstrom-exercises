module Handler where
import Lib (Context(Context, writeQueue), IncomingMessages(..), OutgoingMessages(..), meId, neighbours, serverMsgId, messages, getUUID, NeighbourState (NeighbourState, inflightMessage, messagesToSend))
import qualified Data.Map as Map
import qualified Data.Set as Set
import Control.Concurrent.STM (atomically, writeTQueue, newEmptyTMVarIO)
import Control.Concurrent.STM.TQueue (newTQueueIO)
import Control.Concurrent.Async (async, link)
import Data.Foldable (forM_)
import Control.Monad (forM, when)
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
handler ctx@(Context { neighbours, messages }) srcNode (Broadcast (BroadcastPayload message)) = do
    -- we need to send all broadcast ids we haven't seen yet
    -- find everything in message thats not in messages
    let incomingMessageSet = Set.fromList message
    let newCtx = ctx { messages = Set.union incomingMessageSet messages }

    let toBroadcast = Set.difference incomingMessageSet messages
    when (length toBroadcast > 0) $ do
        -- we need to write to each neighbour now to let them know!
        -- don't tell the person who just told us
        let toTell = map snd $ filter (\(nodeId, _) -> nodeId /= srcNode) $ Map.toList neighbours
        forM_ toTell (\(NeighbourState { messagesToSend }) ->
            atomically (writeTQueue messagesToSend toBroadcast))

    -- and then we're done?
    pure (newCtx, BroadcastOk)
handler ctx@(Context { messages }) _ Read = pure (ctx, ReadOk $ ReadPayload $ Set.toList messages)
handler _ _ (RaftRead _) = undefined
handler _ _ (RaftWrite _) = undefined