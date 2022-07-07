-- |
-- An API for retrieval of multiple results.
-- Can be used to handle:
--
-- * A single result,
--
-- * Individual results of a multi-statement query
-- with the help of "Applicative" and "Monad",
--
-- * Row-by-row fetching.
module Hasql.Private.Errors where

import Hasql.Private.Prelude

-- |
-- An error during the execution of a query.
-- Comes packed with the query template and a textual representation of the provided params.
data QueryError
  = QueryError ByteString [Text] CommandError
  deriving (Show, Eq, Typeable)

instance Exception QueryError

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
      ByteString
      -- ^ __Code__. The SQLSTATE code for the error. It's recommended to use
      -- <http://hackage.haskell.org/package/postgresql-error-codes
      -- the "postgresql-error-codes" package> to work with those.
      ByteString
      -- ^ __Message__. The primary human-readable error message(typically one
      -- line). Always present.
      (Maybe ByteString)
      -- ^ __Details__. An optional secondary error message carrying more
      -- detail about the problem. Might run to multiple lines.
      (Maybe ByteString)
      -- ^ __Hint__. An optional suggestion on what to do about the problem.
      -- This is intended to differ from detail in that it offers advice
      -- (potentially inappropriate) rather than hard facts. Might run to
      -- multiple lines.
      (Maybe Int)
      -- ^ __Position__. Error cursor position as an index into the original
      -- statement string. Positions are measured in characters not bytes.
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
