module Workload where

import Broadcast.Router (UUIDCtx(UUIDCtx), mkContext, context)
import Lib (initializeCommon, Context, Route, reqParser, RouteData)
import Init (InitRoute(InitRoute), InitRoute2(InitRoute2), initRoute, initRoute2)

data Workload = 
    UUIDServer 
    | BroadcastServer UUIDCtx
    | RaftServer

{-
workloadRoutes :: Workload -> [Workload.Route]
workloadRoutes UUIDServer = [RouteInit InitRoute]
-}

{-
What I want to do is;
1. define a list of types that make up 

baseServer :: '[InitRoute, InitRoute2]
baseServer = [InitRoute, InitRoute2]
-}

commonRoutes :: [RouteData]
commonRoutes = [
  initRoute]

workloadRoutes :: Workload -> [RouteData]
workloadRoutes UUIDServer = commonRoutes <> [initRoute2]

-- FIXME(nhs): figure out how to get this into the leaf nodes?
broadcastWorkload :: IO (Workload)
broadcastWorkload = do
  context <- mkContext <$> initializeCommon
  pure $ BroadcastServer context

getContext :: Workload -> Context
getContext (BroadcastServer (UUIDCtx { context })) = context