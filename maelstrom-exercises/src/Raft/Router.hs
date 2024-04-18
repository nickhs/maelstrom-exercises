module Raft.Router where

import Lib (NodeId, Context)

data RaftCtx = RaftCtx { 
    currentTerm :: Int,
    votedFor :: Maybe NodeId,
    context :: Context
}