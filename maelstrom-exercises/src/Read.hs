module Read where
import Data.Aeson (FromJSON)
import GHC.Generics (Generic)

data ReadPayload = ReadPayload {
    messages :: [Int]
} deriving (Show, Eq, Generic)

instance FromJSON ReadPayload where