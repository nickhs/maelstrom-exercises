module Handler where
import Lib (Context(Context, writeQueue), meId, neighbours, serverMsgId, NeighbourState (NeighbourState, inflightMessage, messagesToSend))
import Messaging (IncomingMessages(..), OutgoingMessages(..))
import Control.Concurrent.STM (newEmptyTMVarIO)
import Control.Concurrent.STM.TQueue (newTQueueIO)
import Control.Concurrent.Async (async, link)
import qualified Data.Map as Map
import Control.Monad (forM)
import Init (InitPayload(InitPayload))
import Topology (TopologyPayload (TopologyPayload))
import Sender (nodeSender)
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
{-
handler ctx _ (Init (InitPayload nodeId _nodeIds)) = do
    let newCtx = ctx { meId = nodeId }
    pure (newCtx, InitOk)
-}
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
handler _ _ (RaftRead _) = undefined
handler _ _ (RaftWrite _) = undefined