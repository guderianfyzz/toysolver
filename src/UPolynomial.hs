-- Univalent polynomials
module UPolynomial
  (
    -- * Polynomial type
    Polynomial

  -- * Conversion
  , var
  , constant
  , fromTerms
  , fromMonomial
  , terms

  -- * Query
  , leadingTerm
  , deg

  -- * Operations
  , deriv
  , polyDiv
  , polyMod
  , polyDivMod
  , polyGCD
  , polyLCM

  -- * Monomial
  , Monomial
  , monomialDegree
  , monomialProd
  , monomialDivisible
  , monomialDiv
  , monomialDeriv

  -- * Monic monomial
  , MonicMonomial
  , mmVar
  , mmOne
  , mmDegree
  , mmProd
  , mmDivisible
  , mmDiv
  , mmDeriv
  , mmLCM
  , mmGCD
  ) where

import Data.Function
import Data.List
import qualified Data.Map as Map

newtype Polynomial k = Polynomial (Map.Map Integer k)
  deriving (Eq, Ord, Show)

instance (Eq k, Num k) => Num (Polynomial k) where
  Polynomial m1 + Polynomial m2 = normalize $ Polynomial $ Map.unionWith (+) m1 m2
  Polynomial m1 * Polynomial m2 = normalize $ Polynomial $ Map.fromListWith (+)
      [ (xs1 `mmProd` xs2, c1*c2)
      | (xs1,c1) <- Map.toList m1, (xs2,c2) <- Map.toList m2
      ]
  negate (Polynomial m) = Polynomial $ Map.map negate m
  abs x = x    -- OK?
  signum x = 1 -- OK?
  fromInteger x = constant (fromInteger x)

polyDiv :: (Eq k, Fractional k) => Polynomial k -> Polynomial k -> Polynomial k
polyDiv f1 f2 = fst (polyDivMod f1 f2)

polyMod :: (Eq k, Fractional k) => Polynomial k -> Polynomial k -> Polynomial k
polyMod f1 f2 = snd (polyDivMod f1 f2)

polyDivMod :: (Eq k, Fractional k) => Polynomial k -> Polynomial k -> (Polynomial k, Polynomial k)
polyDivMod f1 f2 = go f1
  where
    m2 = leadingTerm f2
    go 0 = (0,0)
    go f1
      | m1 `monomialDivisible` m2 =
          case go (f1 - fromMonomial (m1 `monomialDiv` m2) * f2) of
            (q,r) -> (q + fromMonomial (m1 `monomialDiv` m2), r)
      | otherwise = (0, f1)
      where
        m1 = leadingTerm f1

test_polyDivMod = f == g*q + r
  where
    x :: Polynomial Rational
    x = var
    f = x^3 + x^2 + x
    g = x^2 + 1
    (q,r) = f `polyDivMod` g

scaleLeadingTermToMonic :: (Eq k, Fractional k) => Polynomial k -> Polynomial k
scaleLeadingTermToMonic f = constant (1/c) * f
  where
    (c,_) = leadingTerm f

polyGCD :: (Eq k, Fractional k) => Polynomial k -> Polynomial k -> Polynomial k
polyGCD f1 0  = scaleLeadingTermToMonic f1
polyGCD f1 f2 = polyGCD f2 (f1 `polyMod` f2)

test_polyGCD = polyGCD f1 f2
  where 
    x :: Polynomial Rational
    x = var
    f1 = x^3 + x^2 + x
    f2 = x^2 + 1

polyLCM :: (Eq k, Fractional k) => Polynomial k -> Polynomial k -> Polynomial k
polyLCM _ 0 = 0
polyLCM 0 _ = 0
polyLCM f1 f2 = scaleLeadingTermToMonic $ (f1 `polyMod` (polyGCD f1 f2)) * f2    

normalize :: (Eq k, Num k) => Polynomial k -> Polynomial k
normalize (Polynomial m) = Polynomial (Map.filter (0/=) m)

var :: (Eq k, Num k) => Polynomial k
var = fromMonomial (1, mmVar)

constant :: (Eq k, Num k) => k -> Polynomial k
constant c = fromMonomial (c, mmOne)

fromTerms :: (Eq k, Num k) => [Monomial k] -> Polynomial k
fromTerms = normalize . Polynomial . Map.fromListWith (+) . map (\(c,xs) -> (xs,c))

fromMonomial :: (Eq k, Num k) => Monomial k -> Polynomial k
fromMonomial (c,xs) = normalize $ Polynomial $ Map.singleton xs c

terms :: Polynomial k -> [Monomial k]
terms (Polynomial m) = [(c,xs) | (xs,c) <- Map.toList m]

leadingTerm :: (Eq k, Num k) => Polynomial k -> Monomial k
leadingTerm (Polynomial p) =
  case Map.maxViewWithKey p of
    Nothing -> (0, mmOne) -- should be error?
    Just ((xs,c), _) -> (c,xs)

deg :: Polynomial k -> Integer
deg = maximum . map monomialDegree . terms

deriv :: (Eq k, Num k) => Polynomial k -> Polynomial k
deriv p = sum [fromMonomial (monomialDeriv m) | m <- terms p]

showPoly :: (Eq k, Ord k, Num k, Show k) => Polynomial k -> String
showPoly p = intercalate " + " [f c xs | (c,xs) <- reverse $ terms p]
  where
    f c 0  = showsPrec 8 c ""
    f c xs = intercalate "*" $ [showsPrec 8 c "" | c /= 1 || xs == mmOne] ++ [g xs]
    g 1 = "x"
    g n = "x" ++ "^" ++ show n

{--------------------------------------------------------------------
  Monomial
--------------------------------------------------------------------}

type Monomial k = (k, MonicMonomial)

monomialDegree :: Monomial k -> Integer
monomialDegree (_,xs) = mmDegree xs

monomialProd :: Num k => Monomial k -> Monomial k -> Monomial k
monomialProd (c1,xs1) (c2,xs2) = (c1*c2, xs1 `mmProd` xs2)

monomialDivisible :: Fractional k => Monomial k -> Monomial k -> Bool
monomialDivisible (c1,xs1) (c2,xs2) = mmDivisible xs1 xs2

monomialDiv :: Fractional k => Monomial k -> Monomial k -> Monomial k
monomialDiv (c1,xs1) (c2,xs2) = (c1 / c2, xs1 `mmDiv` xs2)

monomialDeriv :: (Eq k, Num k) => Monomial k -> Monomial k
monomialDeriv (c,xs) =
  case mmDeriv xs of
    (s,ys) -> (c * fromIntegral s, ys)

{--------------------------------------------------------------------
  Monic Monomial
--------------------------------------------------------------------}

type MonicMonomial = Integer

mmDegree :: MonicMonomial -> Integer
mmDegree = id

mmVar :: MonicMonomial
mmVar = 1

mmOne :: MonicMonomial
mmOne = 0

mmProd :: MonicMonomial -> MonicMonomial -> MonicMonomial
mmProd xs1 xs2 = xs1 + xs2

mmDivisible :: MonicMonomial -> MonicMonomial -> Bool
mmDivisible xs1 xs2 = xs1 >= xs2

mmDiv :: MonicMonomial -> MonicMonomial -> MonicMonomial
mmDiv xs1 xs2 = xs1 - xs2

mmDeriv :: MonicMonomial -> (Integer, MonicMonomial)
mmDeriv xs
  | xs==0     = (0, 0)
  | otherwise = (xs, xs - 1)

mmLCM :: MonicMonomial -> MonicMonomial -> MonicMonomial
mmLCM = max

mmGCD :: MonicMonomial -> MonicMonomial -> MonicMonomial
mmGCD = min
