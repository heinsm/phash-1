{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies     #-}

module PerceptualHash ( imgHash
                      , fileHash
                      ) where

import           Control.Monad.ST         (runST)
import           Data.Array.Repa.Eval     (Elt)
import           Data.Bits                (shiftL, (.|.))
import qualified Data.Vector.Unboxed      as V
import           Data.Word                (Word64)
import           Graphics.Image           (Array, Bilinear (..), Border (Edge),
                                           Image, Pixel (PixelX, PixelY),
                                           RSU (..), X, Y, convolve, crop,
                                           makeImage, readImageY, resize,
                                           transpose, (|*|))
import           Graphics.Image.Interface (Elevator, toVector)
import           Median                   (median)

dct32 :: (Floating e, Array arr Y e) => Image arr Y e
dct32 = makeImage (32,32) gen
    where gen (i,j) = PixelY $ sqrt(2/n) * cos((fromIntegral ((2*i+1) * j) * pi)/(2*n))
          n = 32

idMat :: (Fractional e, Array arr X e) => Image arr X e
idMat = makeImage (5,5)
    (\_ -> PixelX (1/49))

{-# INLINE meanFilter #-}
meanFilter :: (Fractional e, Array arr X e, Array arr cs e) => Image arr cs e -> Image arr cs e
meanFilter = convolve Edge idMat
{-# SCC meanFilter #-}

{-# INLINE size32 #-}
size32 :: Array arr cs e => Image arr cs e -> Image arr cs e
size32 = resize Bilinear Edge (32,32)

crop8 :: Array arr cs e => Image arr cs e -> Image arr cs e
crop8 = crop (0,0) (8,8)

medianImmut :: (Ord e, V.Unbox e, Fractional e) => V.Vector e -> e
medianImmut v = runST $
    median =<< V.thaw v

dct :: (Floating e, Array arr Y e) => Image arr Y e -> Image arr Y e
dct img = dct32 |*| img |*| transpose dct32

{-# INLINE imgHash #-}
{-# SPECIALIZE imgHash :: Image RSU Y Double -> Word64 #-}
imgHash :: (Elevator e, Ord e, Floating e, Elt e) => Image RSU Y e -> Word64
imgHash = asWord64 . aboveMed . V.map (\(PixelY x) -> x) . toVector . crop8 . dct . size32 . meanFilter

asWord64 :: V.Vector Bool -> Word64
asWord64 = V.foldl' (\acc x -> (acc `shiftL` 1) .|. boolToWord64 x) 0
    where boolToWord64 :: Bool -> Word64
          boolToWord64 False = 0
          boolToWord64 True  = 1

aboveMed :: (Fractional e, V.Unbox e, Ord e) => V.Vector e -> V.Vector Bool
aboveMed v =
    let med = medianImmut v
    in V.map (<med) v

fileHash :: FilePath -> IO Word64
fileHash = fmap imgHash . readImageY RSU
