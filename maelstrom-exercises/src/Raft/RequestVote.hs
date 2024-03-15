module Raft.RequestVote where

import Data.Aeson (FromJSON (), ToJSON)
import GHC.Generics (Generic)

data RequestVotePayload = ReadPayload {
    key :: String
} deriving (Show, Eq, Generic)

instance FromJSON RequestVotePayload
instance ToJSON RequestVotePayload

{-
instance FromJSON ReadPayload where
    parseJSON = withObject "Read" $ \o -> do
        key <- o .: "key"
        pure $ ReadPayload key

data ReadPayloadOk = ReadPayloadOk {
    value :: String
} deriving (Show, Eq, Generic)

instance FromJSON ReadPayloadOk
instance ToJSON ReadPayloadOk
-}