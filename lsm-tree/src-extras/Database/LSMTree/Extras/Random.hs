{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP          #-}

module Database.LSMTree.Extras.Random (
    -- * Sampling from uniform distributions
    uniformWithoutReplacement
  , uniformWithReplacement
  , sampleUniformWithoutReplacement
  , sampleUniformWithReplacement
  , withoutReplacement
  , withReplacement
    -- * Sampling from multiple distributions
  , frequency
    -- * Shuffling
  , shuffle
    -- * Generators for specific data types
  , randomByteStringR
    -- * Compatibility
  , splitGen_compat
  , uniform_compat
  ) where

import qualified Data.ByteString as BS
import           Data.List (sortBy, unfoldr)
import           Data.Ord (comparing)
import qualified Data.Set as Set
import qualified System.Random as R
import           System.Random (StdGen, Uniform, uniformR)
import           Text.Printf (printf)

{-------------------------------------------------------------------------------
  Sampling from uniform distributions
-------------------------------------------------------------------------------}

uniformWithoutReplacement :: (Ord a, Uniform a) => StdGen -> Int -> [a]
uniformWithoutReplacement rng n = withoutReplacement rng n uniform_compat

uniformWithReplacement :: Uniform a => StdGen -> Int -> [a]
uniformWithReplacement rng n = withReplacement rng n uniform_compat

sampleUniformWithoutReplacement :: Ord a => StdGen -> Int -> [a] -> [a]
sampleUniformWithoutReplacement rng0 n (Set.fromList -> xs0)
  | n > Set.size xs0 =
      error $
        printf "sampleUniformWithoutReplacement: n > length xs0 for n=%d, length xs0=%d"
               n
               (Set.size xs0)
  | otherwise =
      -- Could use 'withoutReplacement', but this is more efficient.
      take n $ go xs0 rng0
  where
    go !xs !rng = x : go xs' rng'
      where
        (i, rng') = uniformR (0, Set.size xs - 1) rng
        !x        = Set.elemAt i xs
        !xs'      = Set.deleteAt i xs

sampleUniformWithReplacement :: Ord a => StdGen -> Int -> [a] -> [a]
sampleUniformWithReplacement rng0 n (Set.fromList -> xs) =
    withReplacement rng0 n $ \rng ->
      let (i, rng') = uniformR (0, Set.size xs - 1) rng
      in  (Set.elemAt i xs, rng')

withoutReplacement :: Ord a => StdGen -> Int -> (StdGen -> (a, StdGen)) -> [a]
withoutReplacement rng0 n0 sample = take n0 $
    go Set.empty rng0
  where
    go !seen !rng
        | Set.member x seen =     go               seen  rng'
        | otherwise         = x : go (Set.insert x seen) rng'
      where
        (!x, !rng') = sample rng

withReplacement :: StdGen -> Int -> (StdGen -> (a, StdGen)) -> [a]
withReplacement rng0 n0 sample =
    take n0 $ unfoldr (Just . sample) rng0

{-------------------------------------------------------------------------------
  Sampling from multiple distributions
-------------------------------------------------------------------------------}

-- | Chooses one of the given generators, with a weighted random distribution.
-- The input list must be non-empty, weights should be non-negative, and the sum
-- of weights should be non-zero (i.e., at least one weight should be positive).
--
-- Based on the implementation in @QuickCheck@.
frequency :: [(Int, StdGen -> (a, StdGen))] -> StdGen -> (a, StdGen)
frequency xs0 g
  | any ((< 0) . fst) xs0 = error "frequency: frequencies must be non-negative"
  | tot == 0              = error "frequency: at least one frequency should be non-zero"
  | otherwise = pick i xs0
 where
  (i, g') = uniformR (1, tot) g

  tot = sum (map fst xs0)

  pick n ((k,x):xs)
    | n <= k    = x g'
    | otherwise = pick (n-k) xs
  pick _ _  = error "frequency: pick used with empty list"

{-------------------------------------------------------------------------------
  Shuffling
-------------------------------------------------------------------------------}

-- | Create a random permutation of a list.
--
-- Based on the implementation in @QuickCheck@.
shuffle :: [a] -> StdGen -> [a]
shuffle xs g =
    let ns = R.randoms @Int g
    in  map snd (sortBy (comparing fst) (zip ns xs))

{-------------------------------------------------------------------------------
  Generators for specific data types
-------------------------------------------------------------------------------}

-- | Generates a random bytestring. Its length is uniformly distributed within
-- the provided range.
randomByteStringR :: (Int, Int) -> StdGen -> (BS.ByteString, StdGen)
#if MIN_VERSION_random(1,3,0)
randomByteStringR range g =
    let (!l, !g')  = uniformR range g
    in  R.uniformByteString l g'
#else
-- MIN_VERSION_random(1,2,0)
randomByteStringR range g =
    let (!l, !g')  = uniformR range g
    in  R.genByteString l g'
#endif

{-------------------------------------------------------------------------------
  Compatibility
-------------------------------------------------------------------------------}

-- | Alternative to @splitGen@ that is also compatible with versions of
-- random<1.3
--
-- Uses @split@ on @random<1.3@, and @splitGen@ on @random>=1.3@. The former
-- function is deprecated on @random>=1.3@.
splitGen_compat :: StdGen -> (StdGen, StdGen)
#if MIN_VERSION_random(1,3,0)
splitGen_compat = R.splitGen
#else
splitGen_compat = R.split
#endif

-- | Alternative to @uniform@ that is also compatible with versions of
-- random<1.3
--
-- The order of type variables is different on random<1.3 and random>=1.3. This
-- is inconvenient for type application, so we use this compatibility function
-- to ensure that the type variables always have the same ordering.
uniform_compat :: (Uniform a, R.RandomGen g) => g -> (a, g)
uniform_compat = R.uniform

