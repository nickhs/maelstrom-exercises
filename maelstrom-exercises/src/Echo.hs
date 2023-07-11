module Echo where
import qualified Data.Text as T
import Data.Aeson (FromJSON (parseJSON), withObject, (.:))

data Echo = Echo {
    echoPayload :: T.Text
} deriving (Show, Eq)

instance FromJSON Echo where
    parseJSON = withObject "Echo" $ \o -> do
        payload <- o .: "echo"
        pure $ Echo payload