module Init where

import GHC.Generics (Generic)
import Data.Aeson (FromJSON (parseJSON), (.:), withObject)
import qualified Data.Text as T

data InitPayload = InitPayload {
    nodeId :: T.Text,
    nodeIds :: [T.Text]
} deriving (Show, Generic, Eq)

instance FromJSON InitPayload where
    parseJSON = withObject "Init" $ \o -> do
        nodeId <- o .: "node_id"
        nodeIds <- o .: "node_ids"
        pure $ InitPayload { nodeId, nodeIds }