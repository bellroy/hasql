module Hasql.Errors where

import Data.ByteString.Char8 qualified as BC
import Hasql.Prelude

-- | Error during execution of a session.
data SessionError
  = -- |
    -- An error during the execution of a query.
    -- Comes packed with the query template and a textual representation of the provided params.
    QuerySessionError
      -- | SQL template.
      ByteString
      -- | Parameters rendered as human-readable SQL literals.
      [Text]
      -- | Error details
      QueryError
  deriving (Show, Eq, Typeable)

instance Exception SessionError where
  displayException = \case
    QuerySessionError query params commandError ->
      let queryContext :: Maybe (ByteString, Int)
          queryContext = case commandError of
            ClientQueryError _ -> Nothing
            ResultQueryError resultError -> case resultError of
              ServerResultError _ message _ _ (Just position) -> Just (message, position)
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
       in "QuerySessionError!\n"
            <> "\n  Query:\n"
            <> BC.unpack prettyQuery
            <> "\n"
            <> "\n  Params: "
            <> show params
            <> "\n  Error: "
            <> case commandError of
              ClientQueryError (Just message) -> "Client error: " <> show message
              ClientQueryError Nothing -> "Client error without details"
              ResultQueryError resultError -> case resultError of
                ServerResultError code message details hint position ->
                  "Server error "
                    <> BC.unpack code
                    <> ": "
                    <> BC.unpack message
                    <> maybe "" (\d -> "\n  Details: " <> BC.unpack d) details
                    <> maybe "" (\h -> "\n  Hint: " <> BC.unpack h) hint
                UnexpectedResultError message -> "Unexpected result: " <> show message
                RowResultError row (ColumnRowError column rowError) ->
                  "Row error: " <> show row <> ":" <> show column <> " " <> show rowError
                UnexpectedAmountOfRowsResultError amount ->
                  "Unexpected amount of rows: " <> show amount

-- |
-- An error of some command in the session.
data QueryError
  = -- |
    -- An error on the client-side,
    -- with a message generated by the \"libpq\" driver.
    -- Usually indicates problems with connection.
    ClientQueryError (Maybe ByteString)
  | -- |
    -- Some error with a command result.
    ResultQueryError ResultError
  deriving (Show, Eq)

-- |
-- An error with a command result.
data ResultError
  = -- | An error reported by the DB.
    ServerResultError
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
  | -- | The database returned an unexpected result.
    -- Indicates an improper statement or a schema mismatch.
    UnexpectedResultError
      -- | Details.
      Text
  | -- | Error decoding a specific row.
    RowResultError
      -- | Row index.
      Int
      -- | Details.
      RowError
  | -- | Unexpected amount of rows.
    UnexpectedAmountOfRowsResultError
      -- | Actual amount of rows in the result.
      Int
  deriving (Show, Eq)

data RowError
  = -- | Error at a specific column.
    ColumnRowError
      -- | Column index.
      Int
      -- | Error details.
      ColumnError
  deriving (Show, Eq)

-- |
-- Error during the decoding of a specific column.
data ColumnError
  = -- |
    -- Appears on the attempt to parse more columns than there are in the result.
    EndOfInputColumnError
  | -- |
    -- Appears on the attempt to parse a @NULL@ as some value.
    UnexpectedNullColumnError
  | -- |
    -- Appears when a wrong value parser is used.
    -- Comes with the error details.
    ValueColumnError Text
  deriving (Show, Eq)
