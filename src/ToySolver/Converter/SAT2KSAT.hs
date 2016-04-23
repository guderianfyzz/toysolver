{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE FlexibleContexts, MultiParamTypeClasses #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  ToySolver.Converter.SAT2KSAT
-- Copyright   :  (c) Masahiro Sakai 2016
-- License     :  BSD-style
--
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  experimental
-- Portability :  non-portable (FlexibleContexts, MultiParamTypeClasses)
--
-----------------------------------------------------------------------------
module ToySolver.Converter.SAT2KSAT (convert) where

import Control.Monad
import Control.Monad.ST
import Data.Array.IArray
import Data.Array.MArray
import Data.Array.ST
import Data.Foldable (toList)
import Data.Sequence ((<|), (|>))
import qualified Data.Sequence as Seq
import Data.STRef
import qualified Language.CNF.Parse.ParseDIMACS as DIMACS

import qualified ToySolver.SAT.Types as SAT
import ToySolver.SAT.Store.CNF

convert :: Int -> DIMACS.CNF -> (DIMACS.CNF, SAT.Model -> SAT.Model, SAT.Model -> SAT.Model)
convert k _ | k < 3 = error "ToySolver.Converter.SAT2KSAT.convert: k must be >=3"
convert k cnf = runST $ do
  let nv1 = DIMACS.numVars cnf
  db <- newCNFStore
  defsRef <- newSTRef Seq.empty
  SAT.newVars_ db (DIMACS.numVars cnf)
  forM_ (DIMACS.clauses cnf) $ \clause -> do
    let loop lits = do
          if Seq.length lits <= k then
            SAT.addClause db (toList lits)
          else do
            v <- SAT.newVar db
            case Seq.splitAt (k-1) lits of
              (lits1, lits2) -> do
                SAT.addClause db (toList (lits1 |> (-v)))
                modifySTRef' defsRef (|> (v, toList lits1))
                loop (v <| lits2)
    loop $ Seq.fromList (elems clause)
    
  (nv2, cs2) <- getCNFFormula db
  let cnf2 = DIMACS.CNF
             { DIMACS.numVars = nv2
             , DIMACS.numClauses = Seq.length cs2
             , DIMACS.clauses = [listArray (0, length c - 1) c | c <- toList cs2]
             }

  defs <- readSTRef defsRef

  let extendModel :: SAT.Model -> SAT.Model
      extendModel m = runSTUArray $ do
        m2 <- newArray_ (1,nv2)
        forM_ [1..nv1] $ \v -> do
          writeArray m2 v (SAT.evalVar m v)
        forM_ (toList defs) $ \(v, clause) -> do
          let f lit =
                if lit > 0 then
                  readArray m2 lit
                else
                  liftM not (readArray m2 (- lit))
          val <- liftM or (mapM f clause)
          writeArray m2 v val
        return m2

  return (cnf2, extendModel, SAT.restrictModel nv1)

-- -----------------------------------------------------------------------------