module Lib where

import Data.Aeson (FromJSON, withObject, (.:), (.=))
import qualified Data.Aeson as JSON
import Data.Aeson.Types (FromJSON(parseJSON), Pair, Parser)
import Data.UUID ( UUID )
import Echo (Echo(Echo))
import Init (InitPayload)
import Generate (GeneratePayload(GeneratePayload))
import qualified Data.Text as T
import Topology (TopologyPayload)
import Broadcast (broadcastMessage, BroadcastPayload)
import qualified Data.Set as Set
import Data.Map.Strict (Map)
import Control.Concurrent.STM (TQueue, TVar, TMVar)
import Read (ReadPayload (ReadPayload))
import Data.ByteString (ByteString)

data IncomingMessages =
    E Echo
    | Init InitPayload
    | Generate
    | Topology TopologyPayload
    | Broadcast BroadcastPayload
    | Read
    deriving (Show, Eq)

data OutgoingMessages =
    EchoOk Echo
    | InitOk
    | GenerateOk GeneratePayload
    | TopologyOk
    | BroadcastOk
    | ReadOk ReadPayload
    deriving (Show, Eq)

data Messages = Incoming IncomingMessages | Response OutgoingMessages deriving (Show, Eq)

parseMessageJSON :: JSON.Value -> Parser Messages
parseMessageJSON jsonVal = withObject "Message" (\o -> do
        typ <- o .: "type"
        case typ of
            "echo" -> Incoming . E <$> parseJSON jsonVal
            "init" -> Incoming . Init <$> parseJSON jsonVal
            "generate" -> pure $ Incoming Generate
            "topology" -> Incoming . Topology <$> parseJSON jsonVal
            "broadcast" -> Incoming . Broadcast <$> parseJSON jsonVal
            "read" -> pure $ Incoming Read
            "echo_ok" -> Response . EchoOk <$> parseJSON jsonVal
            "init_ok" -> pure $ Response InitOk
            "generate_ok" -> Response . GenerateOk <$> parseJSON jsonVal
            "topology_ok" -> pure $ Response TopologyOk
            "broadcast_ok" -> pure $ Response BroadcastOk
            _ -> fail $ "unknown type " <> typ) jsonVal


instance FromJSON Messages where
    parseJSON = parseMessageJSON

instance FromJSON OutgoingMessages where
    parseJSON jsonVal = do
        -- FIXME(nhs): this feels bad?
        x <- parseMessageJSON jsonVal
        case x of
            (Response r) -> pure r
            _ -> fail "not an outgoing message"

instance FromJSON IncomingMessages where
    parseJSON jsonVal = do
        x <- parseMessageJSON jsonVal
        case x of
            (Incoming r) -> pure r
            (Response _r) -> fail "not an incoming message"

toPairs :: OutgoingMessages -> [Pair]
toPairs (EchoOk (Echo payload)) = ["echo" .= payload]
toPairs InitOk = []
toPairs (GenerateOk (GeneratePayload payload)) = ["id" .= payload]
toPairs TopologyOk = []
toPairs BroadcastOk = []
toPairs (ReadOk (ReadPayload payload))= ["messages" .= payload]

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

data NeighbourState = NeighbourState {
    messagesToSend :: TQueue BroadcastPayload,
    inflightMessage :: TMVar Int -- this is the message id I'm waiting for an ack on
}

data Context = Context {
    getUUID :: IO UUID,
    meId :: NodeId, -- make a better type
    serverMsgId :: TVar Int, -- incrementing message id count
    neighbours :: Map NodeId NeighbourState,
    messages :: Set.Set Int, -- all broadcast message contents we've seen to date
    writeQueue :: TQueue ByteString -- all messages to be send out
}
