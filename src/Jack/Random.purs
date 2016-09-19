module Jack.Random where

import Prelude

import Control.Alt (class Alt, (<|>))
import Control.Lazy (class Lazy, defer)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Random (RANDOM)
import Control.Monad.Rec.Class (class MonadRec, tailRec, tailRecM)
import Control.Monad.State (State, runState, evalState)
import Control.Monad.State.Class (state, modify, get)
import Control.MonadPlus (class MonadPlus)
import Control.MonadZero (class MonadZero)

import Data.Array ((!!), length)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (fold)
import Data.Int53 (Int53)
import Data.Int53 as Int53
import Data.Int as Int
import Data.List (List(..), toUnfoldable)
import Data.Maybe (fromMaybe)
import Data.Monoid.Additive (Additive(..), runAdditive)
import Data.Tuple (Tuple(..), fst, snd)

import Jack.Seed

import Math as Math

-- | Tests are parameterized by the size of the randomly-generated data,
-- | the meaning of which depends on the particular generator used.
type Size =
  Int

--- | A generator for random values of type @a@.
newtype Random a =
  Random (Seed -> Size -> a)

-- | Run a random generator.
runRandom :: forall a. Seed -> Size -> Random a -> a
runRandom seed size (Random r) =
  r seed size

unsafeDelay :: forall a. Random (Random a -> a)
unsafeDelay =
  Random runRandom

unsafePromote :: forall m a. Functor m => m (Random a) -> Random (m a)
unsafePromote m = do
  eval <- unsafeDelay
  pure $ map eval m

-- | Used to construct generators that depend on the size parameter.
sized :: forall a. (Size -> Random a) -> Random a
sized f =
  Random $ \seed size ->
    runRandom seed size (f size)

-- | Overrides the size parameter. Returns a generator which uses the
-- | given size instead of the runtime-size parameter.
resize :: forall a. Size -> Random a -> Random a
resize newSize r =
  Random $ \seed _ ->
    runRandom seed (max 1 newSize) r

-- | /This is not safe when (hi - lo) > 53-bits/
unsafeChooseInt53 :: Int53 -> Int53 -> Random Int53
unsafeChooseInt53 lo hi =
  Random $ \seed _ ->
    fst $ nextInt53 lo hi seed

-- | Generates a random element in the given inclusive range.
chooseInt :: Int -> Int -> Random Int
chooseInt lo hi =
  map Int53.toInt $
  unsafeChooseInt53 (Int53.fromInt lo) (Int53.fromInt hi)

-- | Tail recursive replicate.
replicateRecM :: forall m a. MonadRec m => Int -> m a -> m (List a)
replicateRecM k m =
  let
    go { acc, n } =
      if n <= 0 then
        pure $ Right acc
      else
        map (\x -> Left { acc: Cons x acc, n: n - 1 }) m
  in
    tailRecM go { acc: Nil, n: k }

------------------------------------------------------------------------
-- Instances

instance functorRandom :: Functor Random where
  map f r =
    Random $ \seed size ->
      f (runRandom seed size r)

instance applyRandom :: Apply Random where
  apply =
    ap

instance applicativeRandom :: Applicative Random where
  pure x =
    Random $ \_ _ ->
      x

instance bindRandom :: Bind Random where
  bind r k =
    Random $ \seed size ->
      case splitSeed seed of
        Tuple seed1 seed2 ->
          runRandom seed2 size <<< k $
          runRandom seed1 size r

instance monadRandom :: Monad Random

instance monadRecRandom :: MonadRec Random where
  tailRecM k a0 =
    let
      go { seed, size, a } =
        case splitSeed seed of
          Tuple seed1 seed2 ->
            case runRandom seed1 size $ k a of
              Left a1 ->
                Left { seed: seed2, size, a: a1 }
              Right b ->
                Right b
    in
      Random $ \seed size ->
        tailRec go { seed, size, a: a0 }

instance lazyRandom :: Lazy (Random a) where
  defer f =
    Random $ \seed size ->
      runRandom seed size $ f unit
