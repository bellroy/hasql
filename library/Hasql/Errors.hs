module Hasql.Errors where

import Data.ByteString.Char8 qualified as BC
import Hasql.Prelude

-- | Error during execution of a session.
data SessionError
  = -- | Error during the execution of a query.
    -- Comes packed with the query template and a textual representation of the provided params.
    QueryError
      -- | SQL template.
      ByteString
      -- | Parameters rendered as human-readable SQL literals.
      [Text]
      -- | Error details.
      CommandError
  | -- | Error during the execution of a pipeline.
    PipelineError
      -- | Error details.
      CommandError
  deriving (Show, Eq, Typeable)

instance Exception SessionError where
  displayException = \case
    QueryError query params commandError ->
      let queryContext :: Maybe (ByteString, Int)
          queryContext = case commandError of
            ClientError _ -> Nothing
            ResultError resultError -> case resultError of
              ServerError _ message _ _ (Just position) -> Just (message, position)
              _ -> Nothing

          -- find the line number and position of the error
          findLineAndPos :: ByteString -> Int -> (Int, Int)
          findLineAndPos byteString errorPos =
            let (_, line, pos) =
                  BC.foldl'
                    ( \(total, line, pos) c ->
                        case total + 1 of
                          0 -> (total, line, pos)
                          cursor
                            | cursor == errorPos -> (-1, line, pos + 1)
                            | c == '\n' -> (total + 1, line + 1, 0)
                            | otherwise -> (total + 1, line, pos + 1)
                    )
                    (0, 1, 0)
                    byteString
             in (line, pos)

          formatErrorContext :: ByteString -> ByteString -> Int -> ByteString
          formatErrorContext query message errorPos =
            let lines = BC.lines query
                (lineNum, linePos) = findLineAndPos query errorPos
             in BC.unlines (take lineNum lines)
                  <> BC.replicate (linePos - 1) ' '
                  <> "^ "
                  <> message

          prettyQuery :: ByteString
          prettyQuery = case queryContext of
            Nothing -> query
            Just (message, pos) -> formatErrorContext query message pos
       in "QueryError!\n"
            <> "\n  Query:\n"
            <> BC.unpack prettyQuery
            <> "\n"
            <> "\n  Params: "
            <> show params
            <> "\n  Error: "
            <> renderCommandErrorAsReason commandError
    PipelineError commandError ->
      "PipelineError!\n  Reason: " <> renderCommandErrorAsReason commandError
    where
      renderCommandErrorAsReason = \case
        ClientError (Just message) -> "Client error: " <> show message
        ClientError Nothing -> "Client error without details"
        ResultError resultError -> case resultError of
          ServerError code message details hint position ->
            "Server error "
              <> BC.unpack code
              <> ": "
              <> BC.unpack message
              <> maybe "" (\d -> "\n  Details: " <> BC.unpack d) details
              <> maybe "" (\h -> "\n  Hint: " <> BC.unpack h) hint
          UnexpectedResult message -> "Unexpected result: " <> show message
          RowError row column rowError ->
            "Error in row " <> show row <> ", column " <> show column <> ": " <> show rowError
          UnexpectedAmountOfRows amount ->
            "Unexpected amount of rows: " <> show amount

-- |
-- An error of some command in the session.
data CommandError
  = -- |
    -- An error on the client-side,
    -- with a message generated by the \"libpq\" library.
    -- Usually indicates problems with connection.
    ClientError (Maybe ByteString)
  | -- |
    -- Some error with a command result.
    ResultError ResultError
  deriving (Show, Eq)

-- |
-- An error with a command result.
data ResultError
  = -- | An error reported by the DB.
    ServerError
      -- | __Code__. The SQLSTATE code for the error. It's recommended to use
      -- <http://hackage.haskell.org/package/postgresql-error-codes
      -- the "postgresql-error-codes" package> to work with those.
      ByteString
      -- | __Message__. The primary human-readable error message(typically one
      -- line). Always present.
      ByteString
      -- | __Details__. An optional secondary error message carrying more
      -- detail about the problem. Might run to multiple lines.
      (Maybe ByteString)
      -- | __Hint__. An optional suggestion on what to do about the problem.
      -- This is intended to differ from detail in that it offers advice
      -- (potentially inappropriate) rather than hard facts. Might run to
      -- multiple lines.
      (Maybe ByteString)
      -- | __Position__. Error cursor position as an index into the original
      -- statement string. Positions are measured in characters not bytes.
      (Maybe Int)
  | -- |
    -- The database returned an unexpected result.
    -- Indicates an improper statement or a schema mismatch.
    UnexpectedResult Text
  | -- |
    -- An error of the row reader, preceded by the indexes of the row and column.
    RowError Int Int RowError
  | -- |
    -- An unexpected amount of rows.
    UnexpectedAmountOfRows Int
  deriving (Show, Eq)

-- |
-- An error during the decoding of a specific row.
data RowError
  = -- |
    -- Appears on the attempt to parse more columns than there are in the result.
    EndOfInput
  | -- |
    -- Appears on the attempt to parse a @NULL@ as some value.
    UnexpectedNull
  | -- |
    -- Appears when a wrong value parser is used.
    -- Comes with the error details.
    ValueError Text
  deriving (Show, Eq)
