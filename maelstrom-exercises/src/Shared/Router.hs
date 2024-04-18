module Shared.Router where
import Init (InitPayload (InitPayload))
import Echo (Echo)
import Topology (TopologyPayload)
import Lib (Context (meId), Route)

data Request =
    Init InitPayload
    | E Echo
    | Topology TopologyPayload

data Response =
    InitOk
    | EchoOk Echo
    | TopologyOk

handler :: Context -> Request -> IO (Context, Response)
handler ctx (Init (InitPayload nodeId _nodeIds)) = do
    let newCtx = ctx { meId = nodeId }
    pure (newCtx, InitOk)