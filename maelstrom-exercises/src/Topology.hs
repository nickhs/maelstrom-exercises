module Topology where
import Data.Map (Map)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Data.Aeson (FromJSON)

data TopologyPayload = TopologyPayload {
    topology :: Map T.Text [T.Text]
} deriving (Show, Generic, Eq)

instance FromJSON TopologyPayload