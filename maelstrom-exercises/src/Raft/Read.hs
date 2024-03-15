module Raft.Read where

import Data.Aeson (FromJSON (), ToJSON)
import GHC.Generics (Generic)

data ReadPayload = ReadPayload {
    key :: String
} deriving (Show, Eq, Generic)

instance FromJSON ReadPayload
instance ToJSON ReadPayload

{-
instance FromJSON ReadPayload where
    parseJSON = withObject "Read" $ \o -> do
        key <- o .: "key"
        pure $ ReadPayload key
-}

data ReadPayloadOk = ReadPayloadOk {
    value :: String
} deriving (Show, Eq, Generic)

instance FromJSON ReadPayloadOk
instance ToJSON ReadPayloadOk