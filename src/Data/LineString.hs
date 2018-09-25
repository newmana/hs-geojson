{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NoImplicitPrelude #-}
-------------------------------------------------------------------
-- |
-- Module       : Data.LineString
-- Copyright    : (C) 2014-2018 HS-GeoJSON Project
-- License      : BSD-style (see the file LICENSE.md)
-- Maintainer   : Andrew Newman
--
-- Refer to the GeoJSON Spec <http://geojson.org/geojson-spec.html#linestring>
--
-- A LinearString is a List with at least 2 elements
--
-------------------------------------------------------------------
module Data.LineString (
    -- * Type
        LineString
    ,   ListToLineStringError(..)
    ,   VectorToLineStringError(..)
    -- * Functions
    ,   toVector
    ,   combineToVector
    ,   fromVector
    ,   fromLineString
    ,   fromList
    ,   Data.LineString.map
    ,   Data.LineString.foldr
    ,   Data.LineString.foldMap
    ,   makeLineString
    ,   lineStringHead
    ,   lineStringLast
    ,   lineStringLength
    ) where

import           Prelude             hiding (foldr)

import           Control.Applicative (Applicative (..))
import           Control.DeepSeq
import           Control.Lens        (( # ), (^?))
import           Control.Monad       (mzero)
import           Data.Aeson          (FromJSON (..), ToJSON (..), Value)
import           Data.Aeson.Types    (Parser, typeMismatch)
import           Data.Maybe          (fromMaybe)
import qualified Data.Sequence       as Sequence
import qualified Data.Validation     as Validation
import           GHC.Generics        (Generic)

-- |
-- a LineString has at least 2 elements
--
data LineString a = LineString a a (Sequence.Seq a) deriving (Eq, Generic, NFData)

-- |
-- When converting a List to a LineString, here is a list of things that can go wrong:
--
--     * The list was empty
--     * The list only had one element
--
data ListToLineStringError =
        ListEmpty
    |   SingletonList
    deriving (Eq)

-- |
-- When converting a Vector to a LineString, here is a list of things that can go wrong:
--
--     * The vector was empty
--     * The vector only had one element
--
data VectorToLineStringError =
       VectorEmpty
   |   SingletonVector
   deriving (Eq)

-- functions

-- |
-- returns the element at the head of the string
--
lineStringHead :: LineString a -> a
lineStringHead (LineString x _ _) = x

-- |
-- returns the last element in the string
--
lineStringLast :: (VectorStorable.Storable a) => LineString a -> a
lineStringLast (LineString _ x xs) = fromMaybe x (safeLast xs)

-- |
-- returns the number of elements in the list, including the replicated element at the end of the list.
--
lineStringLength :: (VectorStorable.Storable a) => LineString a -> Int
lineStringLength (LineString _ _ xs) = 2 + VectorStorable.length xs

-- |
-- This function converts it into a list and appends the given element to the end.
--
fromLineString :: (VectorStorable.Storable a) => LineString a -> [a]
fromLineString (LineString x y zs) = x : y : VectorStorable.toList zs

-- |
-- creates a LineString out of a list of elements,
-- if there are enough elements (needs at least 2) elements
--
fromList :: (Validation.Validate v) => [a] -> v ListToLineStringError (LineString a)
fromList []       = Validation._Failure # ListEmpty
fromList [_]      = Validation._Failure # SingletonList
fromList (x:y:zs) = Validation._Success # LineString x y (VectorStorable.fromList zs)
{-# INLINE fromList #-}

-- |
-- create a vector from a LineString by combining values.
-- LineString 1 2 [3,4] (,) --> Vector [(1,2),(2,3),(3,4)]
--
combineToVector :: (VectorStorable.Storable a, VectorStorable.Storable b) => (a -> a -> b) -> LineString a -> Sequence.Seq b
combineToVector combine (LineString a b rest) = VectorStorable.cons (combine a b) combineRest
    where
        combineRest =
          if VectorStorable.null rest
            then
              VectorStorable.empty
            else
              (VectorStorable.zipWith combine <*> VectorStorable.tail) (VectorStorable.cons b rest)
{-# INLINE combineToVector #-}

-- |
-- create a vector from a LineString.
-- LineString 1 2 [3,4] --> Vector [1,2,3,4]
--
toVector :: (VectorStorable.Storable a) => LineString a -> Sequence.Seq a
toVector (LineString a b rest) = VectorStorable.cons a (VectorStorable.cons b rest)
{-# INLINE toVector #-}

-- |
-- creates a LineString out of a vector of elements,
-- if there are enough elements (needs at least 2) elements
--
fromVector :: (Validation.Validate v) => Sequence.Seq a -> v VectorToLineStringError (LineString a)
fromVector (head Sequence.:< tail) =
  if VectorStorable.null v then
    Validation._Failure # VectorEmpty
  else
    fromVector' head tail
{-# INLINE fromVector #-}

fromVector' :: (Validation.Validate v) => a -> Sequence.Seq a -> v VectorToLineStringError (LineString a)
fromVector' first (head Sequence.:< tail) =
  if VectorStorable.null v then
    Validation._Failure # SingletonVector
  else
    Validation._Success # LineString first head tail
{-# INLINE fromVector' #-}

-- |
-- Creates a LineString
-- @makeLineString x y zs@ creates a `LineString` homomorphic to the list @[x, y] ++ zs@
--
makeLineString ::
       a                        -- ^ The first element
    -> a                        -- ^ The second element
    -> Sequence.Seq a  -- ^ The rest of the optional elements
    -> LineString a
makeLineString = LineString

-- instances

instance Show ListToLineStringError where
    show ListEmpty     = "List Empty"
    show SingletonList = "Singleton List"

instance Show VectorToLineStringError where
  show VectorEmpty     = "Vector Empty"
  show SingletonVector = "Singleton Vector"

instance (Show a) => Show (LineString a) where
    show  = show . fromLineString

map :: (a -> b) -> LineString a -> LineString b
map f (LineString x y zs) = LineString (f x) (f y) (fmap f zs)
{-# INLINE map #-}

-- | This will run through the entire ring, closing the
-- loop by also passing the initial element in again at the end.
--
foldr :: (a -> b -> b) -> b -> LineString a -> b
foldr f u (LineString x y zs) = f x (f y (foldr f u zs))
{-# INLINE foldr #-}

foldMap :: (Monoid m) => (a -> m) -> LineString a -> m
foldMap f = foldr (mappend . f) mempty
{-# INLINE foldMap #-}

instance (ToJSON a) => ToJSON (LineString a) where
--  toJSON :: a -> Value
    toJSON = toJSON . fromLineString

instance (FromJSON a, Show a) => FromJSON (LineString a) where
--  parseJSON :: Value -> Parser a
    parseJSON v = do
        xs <- parseJSON v
        let vxs = fromListValidated xs
        maybe (parseError v (vxs ^? Validation._Failure)) return (vxs ^? Validation._Success)

-- helpers

fromListValidated :: [a] -> Validation.Validation ListToLineStringError (LineString a)
fromListValidated = fromList

parseError :: Value -> Maybe ListToLineStringError -> Parser b
parseError v = maybe mzero (\e -> typeMismatch (show e) v)

-- safeLast :: (VectorStorable.Storable a) => Sequence.Seq a -> Maybe a
-- safeLast x = if Sequence.null x then Nothing else Just $ Sequence.last x
safeLast :: Sequence.Seq a -> Maybe a
safeLast x = case Sequence.viewr x of
                Sequence.EmptyR ->  Nothing
                _ Sequence.:> b -> Just b
{-# INLINE safeLast #-}
