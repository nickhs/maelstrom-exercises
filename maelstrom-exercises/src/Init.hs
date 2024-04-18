module Init where

import GHC.Generics (Generic)
import Data.Aeson (FromJSON (parseJSON), (.:), withObject)
import qualified Data.Text as T
import Lib (Route(responseKey, handle, reqParser), meId, Context, Request, Response, respParser, ContextTyp, rdReqParser, rdRespParser, rdHandle, RouteData(..))
import qualified Data.Aeson as JSON
import Data.Aeson.Types (Parser)
import Messaging (MsgEnvelope, MsgBody)

data InitRoute = InitRoute
data InitRoute2 = InitRoute2

data InitPayload = InitPayload {
    nodeId :: T.Text,
    nodeIds :: [T.Text]
} deriving (Show, Generic, Eq)

initRoute :: RouteData
initRoute = RouteData {
    rdReqParser = parseJSON :: JSON.Value -> Parser (MsgEnvelope (MsgBody InitPayload)),
    rdRespParser = \_ -> JSON.object [],
    rdHandle = \context _req -> return (context, ())
}

initRoute2 :: RouteData
initRoute2 = RouteData {
    rdReqParser = (parseJSON :: JSON.Value -> Parser (MsgEnvelope (MsgBody InitPayload))),
    rdRespParser = \_ -> JSON.object [],
    rdHandle = \context _req -> return (context, ())
}

assertJSONType :: T.Text -> JSON.Object -> Parser ()
assertJSONType expectedTyp val = do
    actualTyp <- val .: "type"
    if actualTyp == expectedTyp
    then pure ()
    else fail "Invalid type"

instance FromJSON InitPayload where
    parseJSON :: JSON.Value -> Parser InitPayload
    parseJSON = withObject "Init" $ \o -> do
        _ <- assertJSONType "init" o
        nodeId <- o .: "node_id"
        nodeIds <- o .: "node_ids"
        pure $ InitPayload { nodeId, nodeIds }

-- type Request :: FromJSON a => Type -> a
-- type family Request a
instance Route InitRoute where
    type Request InitRoute = InitPayload
    type Response InitRoute = ()
    type ContextTyp InitRoute = Context
    -- requestKey = "init"
    -- reqParser :: JSON.Value -> Parser (MsgEnvelope (MsgBody InitPayload))
    reqParser _ = parseJSON
    responseKey = "init_ok"
    respParser :: () -> JSON.Value
    respParser = JSON.toJSON
    handle :: Context -> InitPayload -> IO (Context, ())
    handle = undefined

-- type Request :: FromJSON a => Type -> a
-- type family Request a
instance Route InitRoute2 where
    type Request InitRoute2 = InitPayload
    type Response InitRoute2 = ()
    type ContextTyp InitRoute2 = Context
    -- requestKey = "init"
    -- reqParser :: JSON.Value -> Parser (MsgEnvelope (MsgBody InitPayload))
    reqParser _ = parseJSON
    responseKey = "init_ok"
    respParser :: () -> JSON.Value
    respParser = JSON.toJSON
    handle :: Context -> InitPayload -> IO (Context, ())
    handle = undefined


{-
instance Route Context InitPayload () where
    requestKey = "init"
    responseKey = "init_ok"
    handle :: Context -> T.Text -> InitPayload -> IO (Context, ())
    handle ctx _ (InitPayload nodeId _nodeIds) = do
        let newCtx = ctx { meId = nodeId }
        pure (newCtx, ())
-}