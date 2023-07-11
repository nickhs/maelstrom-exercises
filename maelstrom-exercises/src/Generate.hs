module Generate where
import qualified Data.Text as T
import GHC.Generics
import Data.Aeson (FromJSON)

data GeneratePayload = GeneratePayload {
    id :: T.Text
} deriving (Show, Generic, Eq)

instance FromJSON GeneratePayload