module Broadcast where
import qualified Data.Text as T
import Data.Aeson (FromJSON (parseJSON), withObject, (.:))

data BroadcastPayload = BroadcastPayload {
    broadcastMessage :: Int
} deriving (Show, Eq)

instance FromJSON BroadcastPayload where
    parseJSON = withObject "Broadcast" $ \o -> do
        broadcastMessage <- o .: "message"
        pure $ BroadcastPayload broadcastMessage