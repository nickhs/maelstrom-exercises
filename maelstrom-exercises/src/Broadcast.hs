module Broadcast where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON (parseJSON), Value (), withArray, withObject, withScientific, (.:))
import Data.Aeson.Types (Parser)
import qualified Data.Vector as Vector

data BroadcastPayload = BroadcastPayload
  { broadcastMessage :: [Int]
  }
  deriving (Show, Eq)

instance FromJSON BroadcastPayload where
  parseJSON = withObject "Broadcast" $ \o -> do
    let parser x = intFieldMultiParser x <|> intFieldSingleParser x
    broadcastMessage <- o .: "message" >>= parser
    pure $ BroadcastPayload broadcastMessage

intFieldMultiParser :: Value -> Parser [Int]
intFieldMultiParser = withArray "message" (fmap Vector.toList . mapM parseJSON)

intFieldSingleParser :: Value -> Parser [Int]
intFieldSingleParser = withScientific "message" $ \x -> pure [round x]