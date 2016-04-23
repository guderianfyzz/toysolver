{-# LANGUAGE TemplateHaskell, ScopedTypeVariables #-}
module Test.BipartiteMatching (bipartiteMatchingTestGroup) where

import Control.Monad
import qualified Data.Foldable as F
import Data.Hashable
import Data.HashSet (HashSet)
import qualified Data.HashSet as HashSet
import Data.HashMap.Strict (HashMap, (!))
import qualified Data.HashMap.Strict as HashMap
import ToySolver.Combinatorial.BipartiteMatching

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.Tasty.HUnit
import Test.Tasty.TH

prop_minimumWeightPerfectMatching =
  forAll (choose (0,10)) $ \n ->
    let as = HashSet.fromList [1..n]
    in forAll (arbitraryWeight as as) $ \(w' :: HashMap (Int,Int) Rational) ->
         let w a b = w' ! (a,b)
             (obj, m, (ysA,ysB)) = minimumWeightPerfectMatching as as w
         in obj == sum [w a b | (a,b) <- HashSet.toList m] &&
            obj == F.sum ysA + F.sum ysB &&
            and [ya + yb <= w a b | (a,ya) <- HashMap.toList ysA, (b,yb) <- HashMap.toList ysB] &&
            HashSet.size m == n

prop_maximumWeightPerfectMatching =
  forAll (choose (0,10)) $ \n ->
    let as = HashSet.fromList [1..n]
    in forAll (arbitraryWeight as as) $ \(w' :: HashMap (Int,Int) Rational) ->
         let w a b = w' ! (a,b)
             (obj, m, (ysA,ysB)) = maximumWeightPerfectMatching as as w
         in obj == sum [w a b | (a,b) <- HashSet.toList m] &&
            obj == F.sum ysA + F.sum ysB &&
            and [ya + yb >= w a b | (a,ya) <- HashMap.toList ysA, (b,yb) <- HashMap.toList ysB] &&
            HashSet.size m == n

prop_minimumWeightMaximumMatching =
  forAll (choose (0,10)) $ \(nA::Int) ->
  forAll (choose (0,10)) $ \(nB::Int) ->
    let as = HashSet.fromList [1..nA]
        bs = HashSet.fromList [1..nB]
    in forAll (arbitraryWeight as bs) $ \(w' :: HashMap (Int,Int) Rational) ->
         let w a b = w' ! (a,b)
             (obj, m) = minimumWeightMaximumMatching as bs w
         in obj == sum [w a b | (a,b) <- HashSet.toList m] &&
            HashSet.size m == min nA nB

prop_maximumWeightMaximumMatching =
  forAll (choose (0,10)) $ \(nA::Int) ->
  forAll (choose (0,10)) $ \(nB::Int) ->
    let as = HashSet.fromList [1..nA]
        bs = HashSet.fromList [1..nB]
    in forAll (arbitraryWeight as bs) $ \(w' :: HashMap (Int,Int) Rational) ->
         let w a b = w' ! (a,b)
             (obj, m) = maximumWeightMaximumMatching as bs w
         in obj == sum [w a b | (a,b) <- HashSet.toList m] &&
            HashSet.size m == min nA nB

arbitraryWeight :: (Hashable a, Eq a, Hashable b, Eq b, Arbitrary w) => HashSet a -> HashSet b -> Gen (HashMap (a, b) w)
arbitraryWeight as bs =
  liftM HashMap.unions $ forM (HashSet.toList as) $ \a -> do
    liftM HashMap.fromList $ forM (HashSet.toList bs) $ \b -> do
      w <- arbitrary
      return ((a,b),w)

bipartiteMatchingTestGroup :: TestTree
bipartiteMatchingTestGroup = $(testGroupGenerator)