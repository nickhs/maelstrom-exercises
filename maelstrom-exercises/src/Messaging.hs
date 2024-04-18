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
import System.Timeout (timeout)
import Data.Aeson.Types (Pair)
import Data.Proxy (Proxy (Proxy))
import Data.Reflection (reflect)
import Echo (Echo (Echo))
import Generate (GeneratePayload (GeneratePayload))
-- import Init (InitPayload)
import Read (ReadPayload (ReadPayload))
import Topology (TopologyPayload)
import Raft.Read (ReadPayload, ReadPayloadOk)
import Raft.Write (WritePayload)

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

data IncomingMessages
  = E Echo
  -- | Init InitPayload
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
  -- "init" -> Init <$> parseJSON jsonVal
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

