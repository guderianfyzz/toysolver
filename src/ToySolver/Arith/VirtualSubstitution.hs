{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  ToySolver.Arith.VirtualSubstitution
-- Copyright   :  (c) Masahiro Sakai 2014
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-- Naive implementation of virtual substitution
--
-- Reference:
-- 
-- * V. Weispfenning. The complexity of linear problems in fields.
--   Journal of Symbolic Computation, 5(1-2): 3-27, Feb.-Apr. 1988.
-- 
-- * Hirokazu Anai, Shinji Hara. Parametric Robust Control by Quantifier Elimination.
--   J.JSSAC, Vol. 10, No. 1, pp. 41-51, 2003.
--
-----------------------------------------------------------------------------
module ToySolver.Arith.VirtualSubstitution
  ( QFFormula
  , evalQFFormula

  -- * Projection
  , project
  , projectN
  , projectCases
  , projectCasesN

  -- * Constraint solving
  , solve
  , solveQFFormula
  ) where

import Control.Monad
import qualified Data.Foldable as Foldable
import qualified Data.IntMap as IM
import qualified Data.IntSet as IS
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Maybe
import Data.VectorSpace hiding (project)

import ToySolver.Data.ArithRel
import ToySolver.Data.Boolean
import ToySolver.Data.BoolExpr
import qualified ToySolver.Data.LA as LA
import ToySolver.Data.Var

-- | quantifier-free formula
type QFFormula = BoolExpr (LA.Atom Rational)

evalQFFormula :: Model Rational -> QFFormula -> Bool
evalQFFormula m = fold f
  where
    f (ArithRel lhs op rhs) = evalOp op (LA.evalExpr m lhs) (LA.evalExpr m rhs)

project :: Var -> QFFormula -> (QFFormula, Model Rational -> Model Rational)
project x formula = (formula', mt)
  where
    xs = projectCases x formula
    formula' = simplify $ orB [phi | (phi,_) <- xs, phi /= false]
    mt m = head $ do
      (phi, mt') <- xs
      guard $ evalQFFormula m phi
      return $ mt' m

projectN :: VarSet -> QFFormula -> (QFFormula, Model Rational -> Model Rational)
projectN vs2 = f (IS.toList vs2)
  where
    f :: [Var] -> QFFormula -> (QFFormula, Model Rational -> Model Rational)
    f [] formula     = (formula, id)
    f (v:vs) formula = (formula3, mt1 . mt2)
      where
        (formula2, mt1) = project v formula
        (formula3, mt2) = f vs formula2

projectCases :: Var -> QFFormula -> [(QFFormula, Model Rational -> Model Rational)]
projectCases v phi = [(psi, \m -> IM.insert v (LA.evalExpr m t) m) | (psi, t) <- projectCases' v phi]

{-
∃xφ(x) ⇔ ∨_{t∈S} φ(t)
  where
    Ψ = {a_i x - b_i ρ_i 0 | i ∈ I, ρ_i ∈ {=, ≠, ≦, <}} the set of atomic subformulas in φ(x)
    S = {b_i / a_i, b_i / a_i + 1, b_i / a_i - 1 | i∈I } ∪ {1/2 (b_i / a_i + b_j / a_j) | i,j∈I, i≠j}
-}
projectCases' :: Var -> QFFormula -> [(QFFormula, LA.Expr Rational)]
projectCases' v phi = [(applySubst1 v t phi, t) | t <- Set.toList s]
  where
    xs = collect v phi
    s = Set.unions
        [ xs
        , Set.fromList [e ^+^ LA.constant 1 | e <- Set.toList xs]
        , Set.fromList [e ^-^ LA.constant 1 | e <- Set.toList xs]
        , Set.fromList [(e1 ^+^ e2) ^/ 2 | (e1,e2) <- pairs (Set.toList xs)]
        ]

projectCasesN :: VarSet -> QFFormula -> [(QFFormula, Model Rational -> Model Rational)]
projectCasesN vs = f (IS.toList vs) 
  where
    f [] phi = return (phi, id)
    f (v:vs) phi = do
      (phi2, mt1) <- projectCases v phi
      (phi3, mt2) <- f vs phi2
      return (phi3, mt1 . mt2)

collect :: Var -> QFFormula -> Set (LA.Expr Rational)
collect v = Foldable.foldMap f
  where
    f (ArithRel lhs op rhs) =
      case LA.extractMaybe v (lhs ^-^ rhs) of
        Nothing -> Set.empty
        Just (a,b) -> Set.singleton (negateV (b ^/ a))

applySubst1 :: Var -> LA.Expr Rational -> QFFormula -> QFFormula
applySubst1 v t = fold f
  where
    f rel = Atom (LA.applySubst1Atom v t rel)

pairs :: [a] -> [(a,a)]
pairs [] = []
pairs (x:xs) = [(x,x2) | x2 <- xs] ++ pairs xs

solveQFFormula :: VarSet -> QFFormula -> Maybe (Model Rational)
solveQFFormula vs formula = listToMaybe $ do
  (formula2, mt) <- projectCasesN vs formula
  let m = IM.empty
  guard $ evalQFFormula m formula2
  return $ mt m

-- | solve a (open) quantifier-free formula
solve :: VarSet -> [LA.Atom Rational] -> Maybe (Model Rational)
solve vs cs = listToMaybe $ do
  (psi, mt) <- projectCasesN vs (andB [Atom c | c <- cs])
  let m = IM.empty
  guard $ evalQFFormula m psi
  return $ mt m