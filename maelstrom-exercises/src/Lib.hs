module Lib where

import Broadcast (BroadcastPayload, broadcastMessage)
import Control.Concurrent.STM (TMVar, TQueue, TVar)
import Data.Aeson (withObject, (.:), (.=))
import qualified Data.Aeson as JSON
import Data.Aeson.Types (FromJSON (parseJSON), Pair, Parser)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Proxy (Proxy (Proxy))
import Data.Reflection (Reifies, reflect)
import qualified Data.Set as Set
import Data.Tagged (Tagged(Tagged))
import qualified Data.Text as T
import Data.UUID (UUID)
import Echo (Echo (Echo))
import Generate (GeneratePayload (GeneratePayload))
import Init (InitPayload)
import Read (ReadPayload (ReadPayload))
import Topology (TopologyPayload)
import Raft.Read (ReadPayload, ReadPayloadOk)
import Raft.Write (WritePayload)

data IncomingMessages
  = E Echo
  | Init InitPayload
  | Generate
  | Topology TopologyPayload
  | Broadcast BroadcastPayload
  | Read
  | RaftRead Raft.Read.ReadPayload
  | RaftWrite WritePayload
  deriving (Show, Eq)

data OutgoingMessages
  = EchoOk Echo
  | InitOk
  | GenerateOk GeneratePayload
  | TopologyOk
  | BroadcastOk
  | ReadOk Read.ReadPayload
  | RaftReadOk Raft.Read.ReadPayloadOk
  deriving (Show, Eq)

type MsgTypeMap a = JSON.Value -> String -> Parser a
data MessageTypeMaps = TypeMaps (MsgTypeMap IncomingMessages) (MsgTypeMap OutgoingMessages)

mkParserFromTypeMap :: MsgTypeMap a -> JSON.Value -> Parser a
mkParserFromTypeMap typeMap jsonVal =
  withObject
    "Message"
    ( \o -> do
        typ <- o .: "type"
        typeMap jsonVal typ
    )
    jsonVal

broadcastInputTypeMap :: MsgTypeMap IncomingMessages
broadcastInputTypeMap jsonVal typ = case typ of
  "echo" -> E <$> parseJSON jsonVal
  "init" -> Init <$> parseJSON jsonVal
  "generate" -> pure Generate
  "topology" -> Topology <$> parseJSON jsonVal
  "broadcast" -> Broadcast <$> parseJSON jsonVal
  "read" -> pure Read
  _ -> fail $ "unknown input type " <> typ

broadcastOutputMap :: MsgTypeMap OutgoingMessages
broadcastOutputMap jsonVal "echo_ok" = EchoOk <$> parseJSON jsonVal
broadcastOutputMap _ "init_ok" = pure InitOk
broadcastOutputMap jsonVal "generate_ok" = GenerateOk <$> parseJSON jsonVal
broadcastOutputMap _ "topology_ok" = pure TopologyOk
broadcastOutputMap _ "broadcast_ok" = pure BroadcastOk
broadcastOutputMap _ typ = fail $ "unknown output type " <> typ

broadcastTypeMap :: MessageTypeMaps
broadcastTypeMap = TypeMaps broadcastInputTypeMap broadcastOutputMap

raftInputTypeMap :: MsgTypeMap IncomingMessages
raftInputTypeMap jsonVal "read" = RaftRead <$> parseJSON jsonVal

instance {-# OVERLAPPING #-} (Reifies m (MessageTypeMaps)) => JSON.FromJSON (Tagged m IncomingMessages) where
  parseJSON jsonVal = do
    let (TypeMaps typeMap _) :: MessageTypeMaps = reflect (Proxy :: Proxy m)
    let parser = mkParserFromTypeMap typeMap
    x <- parser jsonVal
    pure $ Tagged x

instance {-# OVERLAPPING #-} (Reifies m (MessageTypeMaps)) => JSON.FromJSON (Tagged m OutgoingMessages) where
  parseJSON jsonVal = do
    let (TypeMaps _ typeMap) :: MessageTypeMaps = reflect (Proxy :: Proxy m)
    let parser = mkParserFromTypeMap typeMap
    x <- parser jsonVal
    pure $ Tagged x

toPairs :: OutgoingMessages -> [Pair]
toPairs (EchoOk (Echo payload)) = ["echo" .= payload]
toPairs InitOk = []
toPairs (GenerateOk (GeneratePayload payload)) = ["id" .= payload]
toPairs TopologyOk = []
toPairs BroadcastOk = []
toPairs (ReadOk (ReadPayload payload)) = ["messages" .= payload]

toPairs2 :: IncomingMessages -> [Pair]
toPairs2 (Broadcast payload) = ["message" .= broadcastMessage payload]
toPairs2 _ = error "wat"

messageTypeMapOut :: OutgoingMessages -> String
messageTypeMapOut (EchoOk _) = "echo_ok"
messageTypeMapOut InitOk = "init_ok"
messageTypeMapOut (GenerateOk _) = "generate_ok"
messageTypeMapOut TopologyOk = "topology_ok"
messageTypeMapOut BroadcastOk = "broadcast_ok"
messageTypeMapOut (ReadOk _) = "read_ok"

messageTypeMapOut2 :: IncomingMessages -> String
messageTypeMapOut2 (Broadcast _) = "broadcast"
messageTypeMapOut2 _ = error "wat"

type NodeId = T.Text

type ServerMessageId = TVar Int

data NeighbourState = NeighbourState
  { messagesToSend :: TQueue (Set.Set Int),
    inflightMessage :: TMVar Int -- this is the message id I'm waiting for an ack on
  }

data UUIDCtx = UUIDCtx {
    getUUID :: IO UUID
}

data RaftCtx = RaftCtx { 
    currentTerm :: Int,
    votedFor :: Maybe NodeId
}

data OperatingModes = 
    UUIDServer UUIDCtx 
    | BroadcastServer
    | RaftServer RaftCtx

messageTypeMapLookup :: OperatingModes -> MessageTypeMaps
messageTypeMapLookup (UUIDServer  _) = TypeMaps broadcastInputTypeMap broadcastOutputMap
messageTypeMapLookup BroadcastServer = TypeMaps broadcastInputTypeMap broadcastOutputMap
messageTypeMapLookup (RaftServer _) = TypeMaps broadcastInputTypeMap broadcastOutputMap

data Context = Context
  { meId :: NodeId, -- make a better type
    serverMsgId :: TVar Int, -- incrementing message id count
    neighbours :: Map NodeId NeighbourState,
    messages :: Set.Set Int, -- all broadcast message contents we've seen to date
    writeQueue :: TQueue ByteString, -- all messages to be send out
    messageTypeMap :: MessageTypeMaps -- how to parse the incoming messages
  }