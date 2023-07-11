module Main (main) where
import Server (startServer)
import Lib (Context(Context, serverMsgId, getUUID, messages, neighbours, meId))
import Data.UUID.V4 (nextRandom)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Control.Concurrent.STM.TVar (newTVarIO)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
    msgId <- newTVarIO 0
    hPutStrLn stderr "starting server - listening on stdin..."
    startServer (ctx msgId)

    where ctx msgId = Context {
        serverMsgId = msgId,
        getUUID = nextRandom,
        meId = "",
        messages = Set.empty,
        neighbours = Map.empty
    }