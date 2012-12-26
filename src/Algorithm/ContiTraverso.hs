-----------------------------------------------------------------------------
-- |
-- Module      :  Algorithm.ContiTraverso
-- Copyright   :  (c) Masahiro Sakai 2012
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-- References:
--
-- * P. Conti and C. Traverso, "Buchberger algorithm and integer programming,"
--   Applied Algebra, Algebraic Algorithms and Error-Correcting Codes,
--   Lecture Notes in Computer Science Volume 539, 1991, pp 130-139
--   <http://dx.doi.org/10.1007/3-540-54522-0_102>
--   <http://posso.dm.unipi.it/users/traverso/conti-traverso-ip.ps>
--
-- * IKEGAMI Daisuke, "数列と多項式の愛しい関係," 2011,
--   <http://madscientist.jp/~ikegami/articles/IntroSequencePolynomial.html>
--
-- * 伊藤雅史, , 平林 隆一, "整数計画問題のための b-Gröbner 基底変換アルゴリズム,"
--   <http://www.kurims.kyoto-u.ac.jp/~kyodo/kokyuroku/contents/pdf/1295-27.pdf>
-- 
--
-----------------------------------------------------------------------------
module Algorithm.ContiTraverso
  ( solve
  , solve'
  ) where

import Data.Function
import qualified Data.IntMap as IM
import qualified Data.IntSet as IS
import Data.List
import Data.Monoid
import Data.Ratio

import Data.ArithRel
import Data.Linear
import qualified Data.LA as LA
import Data.Expr (Var, VarSet, Variables (..), Model)
import Data.OptDir
import Data.Polynomial
import Data.Polynomial.GBase
import qualified Algorithm.LPUtil as LPUtil

solve :: MonomialOrder Var -> OptDir -> LA.Expr Rational -> [LA.Atom Rational] -> Maybe (Model Integer)
solve cmp dir obj cs = do
  m <- solve' cmp obj3 cs3
  return . IM.map round . mt . IM.map fromInteger $ m
  where
    ((obj2,cs2), mt) = LPUtil.toStandardForm (if dir == OptMin then obj else lnegate obj, cs)
    obj3 = LA.mapCoeff g obj2
      where
        g = round . (c*)
        c = fromInteger $ foldl' lcm 1 [denominator c | (c,_) <- LA.terms obj]
    cs3 = map f cs2
    f (lhs,rhs) = (LA.mapCoeff g lhs, g rhs)
      where
        g = round . (c*)
        c = fromInteger $ foldl' lcm 1 [denominator c | (c,_) <- LA.terms lhs]

solve' :: MonomialOrder Var -> LA.Expr Integer -> [(LA.Expr Integer, Integer)] -> Maybe (Model Integer)
solve' cmp obj cs
  | or [c < 0 | (c,x) <- LA.terms obj, x /= LA.unitVar] = error "all coefficient of cost function should be non-negative"
  | otherwise =
  if IM.keysSet (IM.filter (/= 0) m) `IS.isSubsetOf` vs'
    then Just $ IM.filterWithKey (\y _ -> y `IS.member` vs') m
    else Nothing

  where
    vs :: [Var]
    vs = IS.toList vs'

    vs' :: VarSet
    vs' = vars $ obj : [lhs | (lhs,_) <- cs]

    v2 :: Var
    v2 = if IS.null vs' then 0 else IS.findMax vs' + 1

    vs2 :: [Var]
    vs2 = [v2 .. v2 + length cs - 1]

    vs2' :: IS.IntSet
    vs2' = IS.fromList vs2

    t :: Var
    t = v2 + length cs

    cmp2 :: MonomialOrder Var
    cmp2 = elimOrdering (IS.fromList vs2) `mappend` elimOrdering (IS.singleton t) `mappend` costOrdering obj `mappend` cmp

    gbase :: [Polynomial Rational Var]
    gbase = buchberger cmp2 (product (map var (t:vs2)) - 1 : phi)
      where
        phi = do
          xj <- vs
          let aj = [(yi, aij) | (yi,(ai,_)) <- zip vs2 cs, let aij = LA.coeff xj ai]
          return $  product [var yi ^ aij    | (yi, aij) <- aj, aij > 0]
                  - product [var yi ^ (-aij) | (yi, aij) <- aj, aij < 0] * var xj

    yb = product [var yi ^ bi | ((_,bi),yi) <- zip cs vs2]

    [(_,z)] = terms (reduce cmp2 yb gbase)

    m = mkModel (vs++vs2++[t]) z

mkModel :: [Var] -> MonicMonomial Var -> Model Integer
mkModel vs xs = mmToIntMap xs `IM.union` IM.fromList [(x, 0) | x <- vs] 
-- IM.union is left-biased

costOrdering :: LA.Expr Integer -> MonomialOrder Var
costOrdering obj = compare `on` f
  where
    vs = vars obj
    f xs = LA.evalExpr (mkModel (IS.toList vs) xs) obj

elimOrdering :: IS.IntSet -> MonomialOrder Var
elimOrdering xs = compare `on` f
  where
    f ys = not (IS.null (xs `IS.intersection` IM.keysSet (mmToIntMap ys)))