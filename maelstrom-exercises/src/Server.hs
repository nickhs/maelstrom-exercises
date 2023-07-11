module Server where
import qualified Data.Aeson as JSON
import Lib
import qualified Data.ByteString.Lazy.Char8 as BSL
import System.IO (hPutStrLn, stderr, hFlush, stdout)
import Messaging (MsgEnvelope(MsgEnvelope, dest), MsgBody(MsgBody), MsgBodyReply(MsgBodyReply), payload, body, Msgs(MsgReq, MsgReply))
import Control.Monad (unless, when)
import Control.Concurrent.STM (atomically, modifyTVar', readTVar, tryReadTMVar, takeTMVar, tryTakeTMVar)
import Debug.Trace (traceShow, traceShowM, traceM)
import Handler (handler)
import Lib (Context(neighbours), OutgoingMessages, NeighbourState (inflightMessage, inflightMessage), Messages (Incoming), IncomingMessages)
import qualified Data.Map as Map

reply :: Context -> MsgEnvelope (MsgBody IncomingMessages) -> IO (Context, MsgEnvelope MsgBodyReply)
reply context (MsgEnvelope src dest (MsgBody incomingMsgId body)) = do
    (newCtx, outMsg) <- handler context body
    nextId <- incrementServerMsgId
    pure $ (newCtx, MsgEnvelope dest src
        (MsgBodyReply incomingMsgId
            (MsgBody nextId outMsg)))

    where
        incrementServerMsgId = atomically $ do
            modifyTVar' (serverMsgId context) (+ 1)
            readTVar $ serverMsgId context

handleResponse :: Context -> MsgEnvelope MsgBodyReply -> IO ()
handleResponse context (MsgEnvelope src _ (MsgBodyReply inReplyTo _)) = do
    let (Just neighbour) = Map.lookup src (neighbours context)
    _ <- atomically $ do
        expected <- tryReadTMVar (inflightMessage neighbour)
        case expected of
            Nothing -> return ()
            (Just expectedId) -> when (inReplyTo == expectedId) $ do
                x <- tryTakeTMVar (inflightMessage neighbour)
                case x of
                    Nothing -> error "wat"
                    (Just _) -> return ()
    return ()

ensureForMe :: Context -> MsgEnvelope a -> Bool
ensureForMe (Context { meId = meId }) (MsgEnvelope { dest = dest }) = meId == dest || meId == ""

startServer :: Context -> IO ()
startServer serverContext = do
    -- we listen for msgs on stdin
    -- I guess we just assume they are newline seperated?
    line <- getLine
    case JSON.eitherDecode (BSL.pack line) of
        Right msg@(MsgEnvelope _ _ msgBody)-> do
            -- ignore messages not for me
            unless (ensureForMe serverContext msg) (startServer serverContext >> fail "unreachable")

            -- route them according to their type
            case msgBody of
                (MsgReq body) -> do
                    let typedMsg = msg { body }
                    (newCtx, result) <- reply serverContext typedMsg
                    let out = JSON.encode result

                    -- and then send back response on stdout
                    putStrLn (BSL.unpack out)
                    hFlush stdout
                    startServer newCtx
                (MsgReply body) -> do
                    let typedMsg = msg { body }
                    -- when we get a response back, we need to find the thread
                    -- that is serving that message queue and let them know
                    -- otherwise they will keep retrying
                    handleResponse serverContext typedMsg
                    startServer serverContext
        Left err -> do
            hPutStrLn stderr $ "could not parse err: " <> err <> " for line " <> line
            startServer serverContext