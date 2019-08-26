module System.Directory.Parallel ( parTraverse ) where

import           Control.Concurrent                  (getNumCapabilities)
import           Control.Concurrent.ParallelIO.Local (Pool, parallel_, withPool)
import           Control.Monad                       (filterM)
import           System.Directory                    (doesDirectoryExist, listDirectory)
import           System.FilePath                     ((</>))

partitionM :: Monad m => (a -> m Bool) -> [a] -> m ([a], [a])
partitionM _ [] = pure ([], [])
partitionM f (x:xs) = do
    res <- f x
    (as,bs) <- partitionM f xs
    if res
        then pure (x:as, bs)
        else pure (as, x:bs)

parTraverse :: (FilePath -> IO ()) -- ^ Action to execute on files
            -> (FilePath -> IO Bool) -- ^ Filter on files
            -> (FilePath -> IO Bool) -- ^ Filter on directories
            -> [FilePath] -- ^ Starting directories
            -> IO ()
parTraverse act fileP dirP dirs = do
    ncpu <- getNumCapabilities
    withPool ncpu $ \pool ->
        parallel_ pool $ fmap (loopPool pool) dirs

    where loopPool :: Pool -> FilePath -> IO ()
          loopPool pool fp = do
                all' <- fmap (fp </>) <$> listDirectory fp
                (dirs', files) <- partitionM doesDirectoryExist all'
                dirs'' <- filterM dirP dirs'
                files' <- filterM fileP files
                parallel_ pool (fmap act files' ++ fmap (loopPool pool) dirs'')
