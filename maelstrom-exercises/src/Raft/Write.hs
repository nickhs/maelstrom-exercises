module Raft.Write where

import Data.Aeson (FromJSON (), ToJSON)
import GHC.Generics (Generic)

data WritePayload = WritePayload {
    key :: String,
    value :: String
} deriving (Show, Eq, Generic)

instance FromJSON WritePayload
instance ToJSON WritePayload