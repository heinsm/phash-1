{-# LANGUAGE ScopedTypeVariables #-}

module Parallel ( pathMaps ) where

import           Control.Concurrent.STM      (atomically)
import           Control.Concurrent.STM.TVar (TVar, modifyTVar', newTVarIO, readTVarIO)
import           Control.Exception           (SomeException, catch)
import           Data.Functor                (($>))
import           Data.List.NonEmpty          (NonEmpty (..), (<|))
import qualified Data.Map                    as M
import           Data.Word                   (Word64)
import           PerceptualHash              (fileHash)
import           System.Directory.Parallel   (parTraverse)
import           System.FilePath             (takeExtension)

imgExtension :: String -> Bool
imgExtension ".jpg"  = True
imgExtension ".jpeg" = True
imgExtension ".png"  = True
imgExtension ".gif"  = True
imgExtension ".ppm"  = True
imgExtension ".hdr"  = True
imgExtension ".bmp"  = True
imgExtension ".TGA"  = True
imgExtension ".tif"  = True
imgExtension ".tiff" = True
imgExtension _       = False

insertHash :: FilePath -> IO (M.Map Word64 (NonEmpty FilePath) -> M.Map Word64 (NonEmpty FilePath))
insertHash fp = do
    hash <- fileHash fp
    pure $ \hashes ->
        case M.lookup hash hashes of
            Just others -> M.insert hash (fp <| others) hashes
            Nothing     -> M.insert hash (fp :| []) hashes

stepMap :: TVar (M.Map Word64 (NonEmpty FilePath)) -> FilePath -> IO ()
stepMap var fp = do
    mod' <- catchWith fp $ insertHash fp
    atomically $ modifyTVar' var mod'

    where catchWith fp' act = catch act $ \(_ :: SomeException) ->
            putStrLn ("WARNING: skipping " ++ fp') $> id

pathMaps :: [FilePath] -> IO (M.Map Word64 (NonEmpty FilePath))
pathMaps fps = do
    total <- newTVarIO mempty
    parTraverse (stepMap total) fileFilter (\_ -> pure True) fps
    readTVarIO total

    where fileFilter = pure . imgExtension . takeExtension
