module Lib where

import Control.Concurrent.STM (TMVar, TQueue, TVar, newTVarIO, newTQueueIO)
import qualified Data.Aeson as JSON
import Data.Aeson.Types (Parser)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Kind (Type)
import qualified Data.Map as Map
import Messaging (MsgEnvelope, MsgBody)

{--

how tf are we going to do this?

for each operating mode we need:
1. a list of requests supported (so shared + specific?)
2. the server context to use

--}

type NodeId = T.Text

type ServerMessageId = TVar Int

data NeighbourState = NeighbourState
  { messagesToSend :: TQueue (Set.Set Int),
    inflightMessage :: TMVar Int -- this is the message id I'm waiting for an ack on
  }

data Context = Context
  { meId :: NodeId, -- make a better type
    serverMsgId :: TVar Int, -- incrementing message id count
    neighbours :: Map NodeId NeighbourState,
    writeQueue :: TQueue ByteString -- all messages to be send out
    -- messageTypeMap :: MessageTypeMaps -- how to parse the incoming messages
  }

initializeCommon :: IO Context
initializeCommon = do
  msgId <- newTVarIO 0
  writeQueue <- newTQueueIO
  pure Context {
    serverMsgId = msgId,
    meId = "",
    neighbours = Map.empty,
    writeQueue = writeQueue
  }

class Route route where
  type Request route
  type Response route
  type ContextTyp route
  -- requestKey :: T.Text
  reqParser :: route -> JSON.Value -> Parser (MsgEnvelope (MsgBody (Request route)))
  responseKey :: T.Text
  respParser :: Response route -> JSON.Value
  handle :: (ContextTyp route) -> (Request route) -> IO (ContextTyp route, Response route)

data RouteData = forall a b. RouteData {
  rdReqParser :: JSON.Value -> Parser (MsgEnvelope (MsgBody a)),
  rdHandle :: Context -> a -> IO (Context, b),
  rdRespParser :: b -> JSON.Value
}

{-
class Request a where
  requestKey :: T.Text
  requestFromJSONParser :: JSON.Value -> a 

class Response a where
  responseKey :: T.Text
  responseToJSONParser :: a -> JSON.Value

class (Request a, Response b) => Route ctx a b where
  handle :: ctx -> a -> b
-}