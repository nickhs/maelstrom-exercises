module Handler where
import Lib (Context(Context), IncomingMessages(..), OutgoingMessages(..), meId, neighbours, serverMsgId, messages, getUUID, NeighbourState (NeighbourState, inflightMessage, messagesToSend))
import qualified Data.Map as Map
import qualified Data.Set as Set
import Control.Concurrent.STM (atomically, writeTQueue, newEmptyTMVarIO)
import Control.Concurrent.STM.TQueue (newTQueueIO)
import Control.Concurrent.Async (async)
import Data.Foldable (forM_)
import Control.Monad (forM)
import Init (InitPayload(InitPayload))
import Generate (GeneratePayload(GeneratePayload))
import Topology (TopologyPayload (TopologyPayload))
import Broadcast (BroadcastPayload (BroadcastPayload), broadcastMessage)
import Data.UUID ( toText )
import Messaging (nodeSender)
import Read (ReadPayload(ReadPayload))

mkNeighbourState :: IO NeighbourState
mkNeighbourState = do
    inflightMessage <- newEmptyTMVarIO
    messagesToSend <- newTQueueIO
    pure NeighbourState {
        inflightMessage,
        messagesToSend
    }

handler :: Context -> IncomingMessages -> IO (Context, OutgoingMessages)
handler ctx (E payload) = pure (ctx, EchoOk payload)
handler ctx (Init (InitPayload nodeId nodeIds)) = do
    let newCtx = ctx { meId = nodeId }
    pure (newCtx, InitOk)
handler ctx Generate = do
    uuid <- toText <$> getUUID ctx
    pure (ctx, GenerateOk $ GeneratePayload uuid)
handler ctx@(Context { serverMsgId, meId }) (Topology (TopologyPayload topo)) = do
    -- add everyone as my neighbour
    let myNeighbours = Set.toList $ Set.delete meId $ Set.fromList $ concat $ Map.elems topo
    -- if I want to be smarter about this
    -- let myNeighbours = fromMaybe [] (Map.lookup (meId ctx) topo)
    tqueues <- zip myNeighbours <$> mapM (const mkNeighbourState) [0..length myNeighbours]
    -- forConcurrently_ tqueues (uncurry (nodeSender (serverMsgId, meId)))

    -- this is so bad but idc anymore FIXME
    asyncHandles <- forM tqueues (\(toNodeId, tqueue) -> async $ nodeSender (serverMsgId, meId) toNodeId tqueue)

    let inited = Map.fromList tqueues
    pure (ctx { neighbours = inited }, TopologyOk)
handler ctx@(Context { neighbours, messages }) (Broadcast bp@(BroadcastPayload message)) = do
    if Set.member message messages
    -- if we've already seen the message then don't broadcast further
    then pure (ctx, BroadcastOk)
    -- otherwise add to our messages and tell all my neighbours!
    else do
        let newCtx = ctx { messages = Set.insert message messages }
        -- we need to write to each neighbour now to let them know!
        -- but only if this is the first time seeing this value
        forM_ (Map.elems neighbours) (\(NeighbourState { messagesToSend }) -> 
            atomically (writeTQueue messagesToSend bp))
        -- and then we're done?
        pure (newCtx, BroadcastOk)
handler ctx@(Context { messages }) Read = pure (ctx, ReadOk $ ReadPayload $ Set.toList messages)