{-# LANGUAGE PackageImports, ScopedTypeVariables, BangPatterns #-}
-- |
-- Copyright   : (c) 2011 Simon Meier
-- License     : BSD3-style (see LICENSE)
--
-- Maintainer  : Simon Meier <iridcode@gmail.com>
-- Stability   : experimental
-- Portability : tested on GHC only
--
-- Benchmark all 'Builder' functions.
module Main (main) where

import Prelude hiding (words)
import Criterion.Main
import Data.Foldable (foldMap)

import qualified Data.ByteString                  as S
import qualified Data.ByteString.Lazy             as L

import           Data.ByteString.Builder
import           Data.ByteString.Builder.ASCII
import           Data.ByteString.Builder.Prim
                   ( FixedPrim, BoundedPrim, (>$<) )
import qualified Data.ByteString.Builder.Prim          as P
import qualified Data.ByteString.Builder.Prim.Internal as PI

import Foreign

------------------------------------------------------------------------------
-- Benchmark support
------------------------------------------------------------------------------

countToZero :: Int -> Maybe (Int, Int)
countToZero 0 = Nothing
countToZero n = Just (n, n - 1)


------------------------------------------------------------------------------
-- Benchmark
------------------------------------------------------------------------------

-- input data (NOINLINE to ensure memoization)
----------------------------------------------

-- | Few-enough repetitions to avoid making GC too expensive.
nRepl :: Int
nRepl = 10000

{-# NOINLINE intData #-}
intData :: [Int]
intData = [1..nRepl]

-- Half of the integers inside the range of an Int and half of them outside.
{-# NOINLINE integerData #-}
integerData :: [Integer]
integerData = map (\x -> fromIntegral x + fromIntegral (maxBound - nRepl `div` 2)) intData

{-# NOINLINE floatData #-}
floatData :: [Float]
floatData = map (\x -> (3.14159 * fromIntegral x) ^ (3 :: Int)) intData

{-# NOINLINE doubleData #-}
doubleData :: [Double]
doubleData = map (\x -> (3.14159 * fromIntegral x) ^ (3 :: Int)) intData

{-# NOINLINE byteStringData #-}
byteStringData :: S.ByteString
byteStringData = S.pack $ map fromIntegral intData

{-# NOINLINE lazyByteStringData #-}
lazyByteStringData :: L.ByteString
lazyByteStringData = case S.splitAt (nRepl `div` 2) byteStringData of
    (bs1, bs2) -> L.fromChunks [bs1, bs2]


-- benchmark wrappers
---------------------

{-# INLINE benchB #-}
benchB :: String -> a -> (a -> Builder) -> Benchmark
benchB name x b =
    bench (name ++" (" ++ show nRepl ++ ")") $
        whnf (L.length . toLazyByteString . b) x

{-# INLINE benchBInts #-}
benchBInts :: String -> ([Int] -> Builder) -> Benchmark
benchBInts name = benchB name intData

-- | Benchmark a 'FixedPrim'. Full inlining to enable specialization.
{-# INLINE benchFE #-}
benchFE :: String -> FixedPrim Int -> Benchmark
benchFE name = benchBE name . P.liftFixedToBounded

-- | Benchmark a 'BoundedPrim'. Full inlining to enable specialization.
{-# INLINE benchBE #-}
benchBE :: String -> BoundedPrim Int -> Benchmark
benchBE name e =
  bench (name ++" (" ++ show nRepl ++ ")") $ benchIntEncodingB nRepl e

-- We use this construction of just looping through @n,n-1,..,1@ to ensure that
-- we measure the speed of the encoding and not the speed of generating the
-- values to be encoded.
{-# INLINE benchIntEncodingB #-}
benchIntEncodingB :: Int              -- ^ Maximal 'Int' to write
                  -> BoundedPrim Int  -- ^ 'BoundedPrim' to execute
                  -> IO ()            -- ^ 'IO' action to benchmark
benchIntEncodingB n0 w
  | n0 <= 0   = return ()
  | otherwise = do
      fpbuf <- mallocForeignPtrBytes (n0 * PI.sizeBound w)
      withForeignPtr fpbuf (loop n0) >> return ()
  where
    loop !n !op
      | n <= 0    = return op
      | otherwise = PI.runB w n op >>= loop (n - 1)



-- benchmarks
-------------

sanityCheckInfo :: [String]
sanityCheckInfo =
  [ "Sanity checks:"
  , " lengths of input data: " ++ show
      [ length intData, length floatData, length doubleData, length integerData
      , S.length byteStringData, fromIntegral (L.length lazyByteStringData)
      ]
  ]

main :: IO ()
main = do
  mapM_ putStrLn sanityCheckInfo
  putStrLn ""
  Criterion.Main.defaultMain
    [ bgroup "Data.ByteString.Builder"
      [ bgroup "Encoding wrappers"
        [ benchBInts "foldMap word8" $
            foldMap (word8 . fromIntegral)
        , benchBInts "primMapListFixed word8" $
            P.primMapListFixed (fromIntegral >$< P.word8)
        , benchB     "primUnfoldrFixed word8" nRepl $
            P.primUnfoldrFixed (fromIntegral >$< P.word8) countToZero
        , benchB     "primMapByteStringFixed word8" byteStringData $
            P.primMapByteStringFixed P.word8
        , benchB     "primMapLazyByteStringFixed word8" lazyByteStringData $
            P.primMapLazyByteStringFixed P.word8
        ]

      , bgroup "Non-bounded encodings"
        [ benchB "foldMap floatDec"        floatData          $ foldMap floatDec
        , benchB "foldMap doubleDec"       doubleData         $ foldMap doubleDec
        , benchB "foldMap integerDec"      integerData        $ foldMap integerDec
        , benchB "byteStringHex"           byteStringData     $ byteStringHex
        , benchB "lazyByteStringHex"       lazyByteStringData $ lazyByteStringHex
        ]
      ]

    , bgroup "Data.ByteString.Builder.Prim"
      [ benchFE "char7"      $ toEnum       >$< P.char7
      , benchFE "char8"      $ toEnum       >$< P.char8
      , benchBE "charUtf8"   $ toEnum       >$< P.charUtf8

      -- binary encoding
      , benchFE "int8"       $ fromIntegral >$< P.int8
      , benchFE "word8"      $ fromIntegral >$< P.word8

      -- big-endian
      , benchFE "int16BE"    $ fromIntegral >$< P.int16BE
      , benchFE "int32BE"    $ fromIntegral >$< P.int32BE
      , benchFE "int64BE"    $ fromIntegral >$< P.int64BE

      , benchFE "word16BE"   $ fromIntegral >$< P.word16BE
      , benchFE "word32BE"   $ fromIntegral >$< P.word32BE
      , benchFE "word64BE"   $ fromIntegral >$< P.word64BE

      , benchFE "floatBE"    $ fromIntegral >$< P.floatBE
      , benchFE "doubleBE"   $ fromIntegral >$< P.doubleBE

      -- little-endian
      , benchFE "int16LE"    $ fromIntegral >$< P.int16LE
      , benchFE "int32LE"    $ fromIntegral >$< P.int32LE
      , benchFE "int64LE"    $ fromIntegral >$< P.int64LE

      , benchFE "word16LE"   $ fromIntegral >$< P.word16LE
      , benchFE "word32LE"   $ fromIntegral >$< P.word32LE
      , benchFE "word64LE"   $ fromIntegral >$< P.word64LE

      , benchFE "floatLE"    $ fromIntegral >$< P.floatLE
      , benchFE "doubleLE"   $ fromIntegral >$< P.doubleLE

      -- host-dependent
      , benchFE "int16Host"  $ fromIntegral >$< P.int16Host
      , benchFE "int32Host"  $ fromIntegral >$< P.int32Host
      , benchFE "int64Host"  $ fromIntegral >$< P.int64Host
      , benchFE "intHost"    $ fromIntegral >$< P.intHost

      , benchFE "word16Host" $ fromIntegral >$< P.word16Host
      , benchFE "word32Host" $ fromIntegral >$< P.word32Host
      , benchFE "word64Host" $ fromIntegral >$< P.word64Host
      , benchFE "wordHost"   $ fromIntegral >$< P.wordHost

      , benchFE "floatHost"  $ fromIntegral >$< P.floatHost
      , benchFE "doubleHost" $ fromIntegral >$< P.doubleHost
      ]

    , bgroup "Data.ByteString.Builder.Prim.ASCII"
      [
      -- decimal number
        benchBE "int8Dec"     $ fromIntegral >$< P.int8Dec
      , benchBE "int16Dec"    $ fromIntegral >$< P.int16Dec
      , benchBE "int32Dec"    $ fromIntegral >$< P.int32Dec
      , benchBE "int64Dec"    $ fromIntegral >$< P.int64Dec
      , benchBE "intDec"      $ fromIntegral >$< P.intDec

      , benchBE "word8Dec"    $ fromIntegral >$< P.word8Dec
      , benchBE "word16Dec"   $ fromIntegral >$< P.word16Dec
      , benchBE "word32Dec"   $ fromIntegral >$< P.word32Dec
      , benchBE "word64Dec"   $ fromIntegral >$< P.word64Dec
      , benchBE "wordDec"     $ fromIntegral >$< P.wordDec

      -- hexadecimal number
      , benchBE "word8Hex"    $ fromIntegral >$< P.word8Hex
      , benchBE "word16Hex"   $ fromIntegral >$< P.word16Hex
      , benchBE "word32Hex"   $ fromIntegral >$< P.word32Hex
      , benchBE "word64Hex"   $ fromIntegral >$< P.word64Hex
      , benchBE "wordHex"     $ fromIntegral >$< P.wordHex

      -- fixed-width hexadecimal numbers
      , benchFE "int8HexFixed"     $ fromIntegral >$< P.int8HexFixed
      , benchFE "int16HexFixed"    $ fromIntegral >$< P.int16HexFixed
      , benchFE "int32HexFixed"    $ fromIntegral >$< P.int32HexFixed
      , benchFE "int64HexFixed"    $ fromIntegral >$< P.int64HexFixed

      , benchFE "word8HexFixed"    $ fromIntegral >$< P.word8HexFixed
      , benchFE "word16HexFixed"   $ fromIntegral >$< P.word16HexFixed
      , benchFE "word32HexFixed"   $ fromIntegral >$< P.word32HexFixed
      , benchFE "word64HexFixed"   $ fromIntegral >$< P.word64HexFixed

      , benchFE "floatHexFixed"    $ fromIntegral >$< P.floatHexFixed
      , benchFE "doubleHexFixed"   $ fromIntegral >$< P.doubleHexFixed
      ]
    ]
