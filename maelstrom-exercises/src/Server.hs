module Server where

import Control.Concurrent.STM (atomically, modifyTVar', readTVar, tryReadTMVar, tryTakeTMVar, writeTQueue)
import Control.Monad (unless, when)
import qualified Data.Aeson as JSON
import qualified Data.Aeson.Types as JSON
import Data.ByteString (toStrict)
import qualified Data.ByteString.Lazy.Char8 as BSL
import Data.Data (Proxy (Proxy))
import qualified Data.Map as Map
import Data.Reflection (reify)
import Data.Tagged (Tagged (Tagged))
import Debug.Trace (traceM)
import Handler (handler)
import Lib (Route, Context(Context), meId, serverMsgId, neighbours, inflightMessage, writeQueue, reqParser, RouteData(RouteData), rdReqParser)
import Messaging (MsgBody (MsgBody), MsgBodyReply (MsgBodyReply), MsgEnvelope (MsgEnvelope, dest), Msgs (MsgReply, MsgReq), body)
import System.IO (hPutStrLn, stderr)
import Messaging (IncomingMessages(..))
import Workload (Workload, getContext)
import Init (InitPayload)

{-
initialize :: OperatingMode -> IO ()
initialize UUIDServer = do
  context <- initializeCommon
  let uuidCtx = UUIDCtx {
    context = context,
    getUUID = nextRandom
  }
  concurrently_ (startServer (ctx msgId writeQueue)) (queueWriter writeQueue)
-}

reply :: Context -> MsgEnvelope (MsgBody IncomingMessages) -> IO (Context, MsgEnvelope MsgBodyReply)
reply context (MsgEnvelope recvSrc _ (MsgBody incomingMsgId body)) = do
  (newCtx, outMsg) <- handler context recvSrc body
  nextId <- incrementServerMsgId
  pure
    ( newCtx,
      MsgEnvelope
        (meId newCtx)
        recvSrc
        ( MsgBodyReply
            incomingMsgId
            ( MsgBody nextId outMsg
            )
        )
    )
  where
    -- FIXME(nickhs): move to common function
    incrementServerMsgId = atomically $ do
      modifyTVar' (serverMsgId context) (+ 1)
      readTVar $ serverMsgId context

-- this is messed up because it looks like it changes nothing
-- but it does change the mvars
-- FIXME clean this up jfc
handleResponse :: Context -> MsgEnvelope MsgBodyReply -> IO ()
handleResponse context (MsgEnvelope src _ msg@(MsgBodyReply inReplyTo _)) = do
  let (Just neighbour) = Map.lookup src (neighbours context)
  _ <- atomically $ do
    expected <- tryReadTMVar (inflightMessage neighbour)
    case expected of
      Nothing -> do
        traceM $ "HERE WHY " ++ show msg
      (Just expectedId) -> when (inReplyTo == expectedId) $ do
        x <- tryTakeTMVar (inflightMessage neighbour)
        case x of
          Nothing -> error "wat"
          (Just _) -> do
            return ()
  return ()

ensureForMe :: Context -> MsgEnvelope a -> Bool
ensureForMe (Context {meId = meId}) (MsgEnvelope {dest = dest}) = meId == dest || meId == ""

{-
handle :: Route r => r -> BSL.ByteString -> Either String (MsgEnvelope (MsgBody r))
handle routes line = do
  -- is it valid json?
  (value :: JSON.Value) <- JSON.eitherDecode line

  -- can we parse it into a route?
  let x = map reqParser routes
  let (JSON.Success a) = mconcat $ map (\p -> JSON.parse p value) x
  undefined
-}

jsonDecode2 :: [RouteData] -> BSL.ByteString -> Either String (MsgEnvelope a)
jsonDecode2 routes line = do
  (jsonVal :: JSON.Value) <- JSON.eitherDecode line
  let result = map (tryParse jsonVal) routes
  undefined
  where
    tryParse jsonVal (RouteData { rdReqParser }) = rdReqParser jsonVal


jsonDecode :: Context -> BSL.ByteString -> Either String (MsgEnvelope Msgs)
jsonDecode ctx line = do
  -- let typeMaps = messageTypeMap ctx
  let typeMaps = undefined
  reify
    typeMaps
    ( \(Proxy :: Proxy m) -> do
        let decoded :: Either String (MsgEnvelope (Tagged m Msgs)) = JSON.eitherDecode line
        -- FIXME(nhs) use bimap
        case decoded of
          Right env@(MsgEnvelope _ _ (Tagged msg)) -> Right $ env {body = msg}
          Left err -> Left err
    )

handleLine :: Workload -> BSL.ByteString -> IO Workload
handleLine workload line = case jsonDecode serverContext line of
  Right msg@(MsgEnvelope _ _ msgBody) -> do
    -- traceM $ "got msg! " ++ show msg
    -- ignore messages not for me
    unless (ensureForMe serverContext msg) (fail "message sent to wrong person?")

    -- route them according to their type
    case msgBody of
      (MsgReq body) -> do
        let typedMsg = msg {body}
        (newCtx, result) <- reply serverContext typedMsg
        let resultRaw = toStrict $ JSON.encode result
        atomically $ writeTQueue (writeQueue serverContext) resultRaw
        undefined
        -- pure newCtx
      (MsgReply body) -> do
        let typedMsg = msg {body}
        -- when we get a response back, we need to find the thread
        -- that is serving that message queue and let them know
        -- otherwise they will keep retrying
        handleResponse serverContext typedMsg
        undefined
        -- pure serverContext
  Left err -> do
    hPutStrLn stderr $ "could not parse err: " <> err <> " for line " <> BSL.unpack line
    -- pure serverContext
    undefined
  where
    serverContext = getContext workload

startServer :: Workload -> IO ()
startServer workload = do
  -- we listen for msgs on stdin
  -- I guess we just assume they are newline seperated?
  line <- getLine
  newCtx <- handleLine workload (BSL.pack line)
  startServer newCtx