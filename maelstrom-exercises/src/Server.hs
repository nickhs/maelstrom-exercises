module Server where
import qualified Data.Aeson as JSON
import Lib
import qualified Data.ByteString.Lazy.Char8 as BSL
import System.IO (hPutStrLn, stderr)
import Messaging (MsgEnvelope(MsgEnvelope, dest), MsgBody(MsgBody), MsgBodyReply(MsgBodyReply), body, Msgs(MsgReq, MsgReply))
import Control.Monad (unless, when)
import Control.Concurrent.STM (atomically, modifyTVar', readTVar, tryReadTMVar, tryTakeTMVar, writeTQueue)
import Debug.Trace (traceM)
import Handler (handler)
import qualified Data.Map as Map
import Data.ByteString (toStrict)

reply :: Context -> MsgEnvelope (MsgBody IncomingMessages) -> IO (Context, MsgEnvelope MsgBodyReply)
reply context (MsgEnvelope recvSrc _ (MsgBody incomingMsgId body)) = do
    (newCtx, outMsg) <- handler context recvSrc body
    nextId <- incrementServerMsgId
    pure $ (newCtx, MsgEnvelope (meId newCtx) recvSrc
        (MsgBodyReply incomingMsgId
            (MsgBody nextId outMsg)))

    where
        -- FIXME(nickhs): move to common function
        incrementServerMsgId = atomically $ do
            modifyTVar' (serverMsgId context) (+ 1)
            readTVar $ serverMsgId context

-- this is messed up because it looks like it changes nothing
-- but it does change the mvars
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
ensureForMe (Context { meId = meId }) (MsgEnvelope { dest = dest }) = meId == dest || meId == ""

handleLine :: Context -> BSL.ByteString -> IO Context
handleLine serverContext line = do
    case JSON.eitherDecode line of
        Right msg@(MsgEnvelope _ _ msgBody)-> do
            -- traceM $ "got msg! " ++ show msg
            -- ignore messages not for me
            unless (ensureForMe serverContext msg) (fail "message sent to wrong person?")

            -- route them according to their type
            case msgBody of
                (MsgReq body) -> do
                    let typedMsg = msg { body }
                    (newCtx, result) <- reply serverContext typedMsg
                    let resultRaw = toStrict $ JSON.encode result
                    atomically $ writeTQueue (writeQueue serverContext) resultRaw
                    pure newCtx
                (MsgReply body) -> do
                    let typedMsg = msg { body }
                    -- when we get a response back, we need to find the thread
                    -- that is serving that message queue and let them know
                    -- otherwise they will keep retrying
                    handleResponse serverContext typedMsg
                    pure serverContext
        Left err -> do
            hPutStrLn stderr $ "could not parse err: " <> err <> " for line " <> (BSL.unpack line)
            pure serverContext

startServer :: Context -> IO ()
startServer serverContext = do
    -- we listen for msgs on stdin
    -- I guess we just assume they are newline seperated?
    line <- getLine
    newCtx <- handleLine serverContext (BSL.pack line)
    startServer newCtx