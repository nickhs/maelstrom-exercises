module Raft.Cas where

import Data.Aeson (FromJSON (), ToJSON)
import GHC.Generics (Generic)

data CasPayload = CasPayload {
    key :: String,
    from :: String,
    to :: String
} deriving (Show, Eq, Generic)

instance FromJSON CasPayload
instance ToJSON CasPayload