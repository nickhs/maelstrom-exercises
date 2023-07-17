module Main (main) where
import Server (startServer)
import Lib (Context(Context, serverMsgId, getUUID, messages, neighbours, meId, writeQueue))
import Data.UUID.V4 (nextRandom)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Control.Concurrent.STM.TVar (newTVarIO)
import Control.Concurrent.STM (newTQueueIO, TQueue, readTQueue, atomically)
import System.IO (hPutStrLn, stderr, stdout, hFlush)
import Control.Concurrent.Async (concurrently_)
import qualified Data.ByteString as BS

queueWriter :: TQueue BS.ByteString -> IO ()
queueWriter queue = do
    -- traceM $ "waiting on message"
    msg <- atomically $ readTQueue queue
    BS.hPut stdout msg
    BS.hPut stdout "\n"
    hFlush stdout
    -- traceM $ "wrote message " <> show msg
    queueWriter queue

main :: IO ()
main = do
    msgId <- newTVarIO 0
    writeQueue <- newTQueueIO
    hPutStrLn stderr "starting server - listening on stdin..."
    concurrently_ (startServer (ctx msgId writeQueue)) (queueWriter writeQueue)

    where ctx msgId writeQueue = Context {
        serverMsgId = msgId,
        getUUID = nextRandom,
        meId = "",
        messages = Set.empty,
        neighbours = Map.empty,
        writeQueue = writeQueue
    }