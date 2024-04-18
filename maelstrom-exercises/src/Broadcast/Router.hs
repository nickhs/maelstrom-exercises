module Broadcast.Router where
import Broadcast (BroadcastPayload (BroadcastPayload))
import Generate (GeneratePayload (GeneratePayload))
import Read (ReadPayload(ReadPayload))
import qualified Data.Map as Map
import Data.UUID (UUID, toText)
import Data.Aeson (parseJSON)
import Lib (Context (neighbours), NeighbourState (NeighbourState, messagesToSend), initializeCommon)
-- import Messaging (MsgTypeMap)
import Data.UUID.V4 (nextRandom)
import qualified Data.Set as Set
import qualified Data.Text as T
import Control.Monad (when)
import Data.Foldable (forM_)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TQueue (writeTQueue)
import qualified Shared.Router

data Request =
    Generate
    | Broadcast BroadcastPayload
    | Read

data Response =
    GenerateOk GeneratePayload
    | BroadcastOk
    | ReadOk ReadPayload

-- FIXME(nhs): break up into uuid and broadcast
data UUIDCtx = UUIDCtx {
    getUUID :: IO UUID,
    messages :: Set.Set Int,
    context :: Context
}

data Requests = Requests Shared.Router.Request Request
data Responses = Responses Shared.Router.Response Response

{-
requestTypeMap :: MsgTypeMap Request
requestTypeMap jsonVal "broadcast" = Broadcast <$> parseJSON jsonVal
requestTypeMap _jsonVal "read" = pure $ Read
requestTypeMap _jsonVal typ = fail $ "unknown request type " <> typ

responseTypeMap :: MsgTypeMap Response
responseTypeMap _ "broadcast_ok" = pure BroadcastOk
responseTypeMap _ typ = fail $ "unknown response type " <> typ
-}

mkContext :: Context -> UUIDCtx
mkContext ctx = UUIDCtx {
    context = ctx,
    messages = Set.empty,
    getUUID = nextRandom
}

handler :: UUIDCtx -> T.Text -> Request -> IO (UUIDCtx, Response)
handler ctx _ Generate = do
    uuid <- toText <$> getUUID ctx
    pure (ctx, GenerateOk $ GeneratePayload uuid)
handler ctx@(UUIDCtx { context, messages }) srcNode (Broadcast (BroadcastPayload message)) = do
    -- we need to send all broadcast ids we haven't seen yet
    -- find everything in message thats not in messages
    let incomingMessageSet = Set.fromList message
    let newCtx = ctx { messages = Set.union incomingMessageSet messages }

    let toBroadcast = Set.difference incomingMessageSet messages
    when (length toBroadcast > 0) $ do
        -- we need to write to each neighbour now to let them know!
        -- don't tell the person who just told us
        let toTell = map snd $ filter (\(nodeId, _) -> nodeId /= srcNode) $ Map.toList (neighbours context)
        forM_ toTell (\(NeighbourState { messagesToSend }) ->
            atomically (writeTQueue messagesToSend toBroadcast))

    -- and then we're done?
    pure (newCtx, BroadcastOk)
handler ctx@(UUIDCtx { messages }) _ Read = pure (ctx, ReadOk $ ReadPayload $ Set.toList messages)