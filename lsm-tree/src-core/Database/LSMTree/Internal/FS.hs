module Database.LSMTree.Internal.FS (
    -- * Hard links
    hardLink
  , hardLinkDirectoryRecursive
    -- * Copy file
  , copyFile
    -- * Hard links with fallback
  , Mode (..)
  , hardLinkOrCopyDirectoryRecursive
  ) where

import           Control.ActionRegistry
import           Control.Monad (forM_, void)
import           Control.Monad.Class.MonadThrow
import           Control.Monad.Primitive (PrimMonad)

import           Foreign.C.Error (eXDEV)
import qualified System.FS.API as FS
import           System.FS.API
import qualified System.FS.API.Lazy as FSL
import qualified System.FS.BlockIO.API as FS
import           System.FS.BlockIO.API (HasBlockIO)
import           Text.Printf (printf)

{-------------------------------------------------------------------------------
  Hard links
-------------------------------------------------------------------------------}

{-# SPECIALISE
  hardLink ::
       HasFS IO h
    -> HasBlockIO IO h
    -> ActionRegistry IO
    -> FS.FsPath
    -> FS.FsPath
    -> IO ()
  #-}
-- | @'hardLink' hfs hbio reg sourcePath destinationPath@ creates a hard link from
-- @sourcePath@ to @destinationPath@.
--
-- Both the source path and destination path should be on the same disk volume.
hardLink ::
     (MonadMask m, PrimMonad m)
  => HasFS m h
  -> HasBlockIO m h
  -> ActionRegistry m
  -> FS.FsPath
  -> FS.FsPath
  -> m ()
hardLink hfs hbio reg sourcePath destinationPath = do
    withRollback_ reg
      (FS.createHardLink hbio sourcePath destinationPath)
      (FS.removeFile hfs destinationPath)

{-# SPECIALISE
  hardLinkDirectoryRecursive ::
       HasFS IO h
    -> HasBlockIO IO h
    -> ActionRegistry IO
    -> FS.FsPath
    -> FS.FsPath
    -> IO ()
  #-}
-- | Recursively create hard links for all the directory contents of the source
-- path at the destination path.
--
-- Both the source path and destination path should be on the same disk volume.
hardLinkDirectoryRecursive ::
     (MonadMask m, PrimMonad m)
  => HasFS m h
  -> HasBlockIO m h
  -> ActionRegistry m
     -- | Source path
  -> FS.FsPath
     -- | Destination path
  -> FS.FsPath
  -> m ()
hardLinkDirectoryRecursive hfs hbio reg sourcePath destinationPath = do
    entries <- FS.listDirectory hfs sourcePath
    forM_ entries $ \entry -> do
      let sourcePath' = sourcePath FS.</> FS.mkFsPath [entry]
          destinationPath' = destinationPath FS.</> FS.mkFsPath [entry]
      isFile <- FS.doesFileExist hfs sourcePath'
      if isFile then
        hardLink hfs hbio reg sourcePath' destinationPath'
      else do
        isDirectory <- FS.doesDirectoryExist hfs sourcePath'
        if isDirectory then do
          hardLinkDirectoryRecursive hfs hbio reg sourcePath' destinationPath'
        else
          error $ printf
            "hardLinkDirectoryRecursive: %s is not a file or directory"
            (show sourcePath')

{-------------------------------------------------------------------------------
  Copy file
-------------------------------------------------------------------------------}

{-# SPECIALISE
  copyFile ::
       HasFS IO h
    -> ActionRegistry IO
    -> FS.FsPath
    -> FS.FsPath
    -> IO ()
  #-}
-- | @'copyFile' hfs reg sourcePath destinationPath@ copies the file contents of
-- @sourcePath@ to the @destinationPath@.
copyFile ::
     (MonadMask m, PrimMonad m)
  => HasFS m h
  -> ActionRegistry m
  -> FS.FsPath
  -> FS.FsPath
  -> m ()
copyFile hfs = copyFile' hfs hfs

{-# SPECIALISE
  copyFile' ::
       HasFS IO h
    -> HasFS IO h'
    -> ActionRegistry IO
    -> FS.FsPath
    -> FS.FsPath
    -> IO ()
  #-}
-- | @'copyFile' sourceFS destinationFS reg sourcePath destinationPath@ copies the file
--   contents of @sourcePath@ on @sourceFS@ to the @destinationPath@ on @destinationFS@.
copyFile' ::
     (MonadMask m, PrimMonad m)
  => HasFS m h  -- ^ The 'HasFS' instance for the source filesystem
  -> HasFS m h' -- ^ The 'HasFS' instance for the target filesystem
  -> ActionRegistry m
  -> FS.FsPath
  -> FS.FsPath
  -> m ()
copyFile' sourceFS destinationFS reg sourcePath destinationPath =
    flip (withRollback_ reg) (FS.removeFile destinationFS destinationPath) $
      FS.withFile sourceFS sourcePath FS.ReadMode $ \sourceHandle ->
        FS.withFile destinationFS destinationPath (FS.WriteMode FS.MustBeNew) $ \destinationHandle -> do
          bs <- FSL.hGetAll sourceFS sourceHandle
          void $ FSL.hPutAll destinationFS destinationHandle bs

{-------------------------------------------------------------------------------
  Hard link with fallback
-------------------------------------------------------------------------------}

{- |
The file transfer mode to be used by a snapshot import or export.
-}
data Mode m h
  = HardLink
    -- | Whether or not to allow fallback to copying.
    !Bool
    -- | The 'HasBlockIO' instance that enables hard linking.
    !(HasBlockIO m h)
  | forall h'.
    Copy
    -- | The 'HasFS' instance that enables copying.
    !(HasFS m h')

{-# SPECIALISE
  hardLinkOrCopy ::
       HasFS IO h
    -> Mode IO h
    -> ActionRegistry IO
    -> FS.FsPath
    -> FS.FsPath
    -> IO ()
  #-}
-- | @'hardLinkOrCopy' sourceFS mode hbio reg sourcePath destinationPath@
--   attempts to create a hard link or create a copy from @sourcePath@ to
--   @destinationPath@ depending on the @mode@
--
-- If @mode = HardLink b hbio@, then this functions attemtps to create a hard
-- link from @sourcePath@ to @destinationPath@ if both are on the same file
-- system and copies the file otherwise (if @b == True@).
--
-- If @mode = Copy destinationFS@, then this function copies from @sourcePath@
-- to @destinationPath@, where the latter is interpreted with respect to
-- @destinationFS@
hardLinkOrCopy ::
  (MonadMask m, PrimMonad m)
  => -- | The 'HasFS' instance for the source filesystem
     HasFS m h
  -> -- | Either a 'HasBlockIO' instance for the source filesystem,
     --   or a 'HasFS' instance for the destination filesystem
     Mode m h
  -> ActionRegistry m
  -> FS.FsPath         -- ^ The source path
  -> FS.FsPath         -- ^ The destination path
  -> m ()
hardLinkOrCopy sourceFS (HardLink fallback sourceBIO) reg sourcePath destinationPath = do
  let -- NOTE: On Windows, the error code is ERROR_NOT_SAME_DEVICE (17),
      --       but the Win32 primitive for creating hard links maps this
      --       to the POSIX error code EXDEV using the maperrno builtin.
      isEXDEV :: FsError -> Bool
      isEXDEV e = fsErrorNo e == Just eXDEV
      ifEXDEV e = if isEXDEV e then Just e else Nothing

      doHardLink = hardLink sourceFS sourceBIO reg sourcePath destinationPath
      doFallBack = copyFile sourceFS reg sourcePath destinationPath
      doHardLinkThenFallBack = catchJust ifEXDEV doHardLink (const doFallBack)

  if fallback then doHardLinkThenFallBack else doHardLink

hardLinkOrCopy sourceFS (Copy destinationFS) reg sourcePath destinationPath =
  copyFile' sourceFS destinationFS reg sourcePath destinationPath

{-# SPECIALISE
  hardLinkOrCopyDirectoryRecursive ::
       HasFS IO h
    -> Mode IO h
    -> ActionRegistry IO
    -> FS.FsPath
    -> FS.FsPath
    -> IO ()
  #-}
hardLinkOrCopyDirectoryRecursive ::
     (MonadMask m, PrimMonad m)
  => -- | The 'HasFS' instance for the source filesystem
     HasFS m h
  -> -- | Either a 'HasBlockIO' instance for the source filesystem,
     --   or a 'HasFS' instance for the destination filesystem
     Mode m h
  -> ActionRegistry m
     -- | Source path
  -> FS.FsPath
     -- | Destination path
  -> FS.FsPath
  -> m ()
hardLinkOrCopyDirectoryRecursive sourceFS mode reg sourcePath destinationPath = do
  entries <- FS.listDirectory sourceFS sourcePath
  forM_ entries $ \entry -> do
    let sourcePath' = sourcePath FS.</> FS.mkFsPath [entry]
        destinationPath' = destinationPath FS.</> FS.mkFsPath [entry]
    isFile <- FS.doesFileExist sourceFS sourcePath'
    if isFile then
      hardLinkOrCopy sourceFS mode reg sourcePath' destinationPath'
    else do
      isDirectory <- FS.doesDirectoryExist sourceFS sourcePath'
      if isDirectory then do
        hardLinkOrCopyDirectoryRecursive sourceFS mode reg sourcePath' destinationPath'
      else
        error $ printf
          "hardLinkOrCopyDirectoryRecursive: %s is not a file or directory"
          (show sourcePath')
