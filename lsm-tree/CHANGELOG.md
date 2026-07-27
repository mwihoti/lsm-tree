# Revision history for `lsm-tree`

## 1.2.0.0 -- 2026-07-27

### Breaking changes

* The constructor for `SnapshotImportDirDoesNotExistError` was renamed to
  `ErrSnapshotImportDirDoesNotExist` and its field is now of type `FsErrorPath`.

* The constructor for `SnapshotExportDirExistsError` was renamed to
  `ErrSnapshotExportDirExists`  and its field is now of type `FsErrorPath`.

* The type of `importSnapshot` was changed from...

  ```hs
  importSnapshot ::
    forall m h.
    (IOLike m) =>
    Session m ->
    SnapshotName ->
    FsPath ->
    m ()
  ```

  ...to...

  ```hs
  importSnapshot ::
    forall m h.
    (IOLike m) =>
    Session m ->
    SnapshotName ->
    (Maybe (HasFS m h), FsPath) ->
    m ()
  ```

  In the previous release, the source directory was passed as an `FsPath`,
  which was interpreted relative to the session mount point. From this release
  onwards, it is passed as a pair of an `FsPath` with an optional `HasFS`
  instance. If the `HasFS` instance is provided, the `FsPath` path is
  interpreted as a path in the corresponding filesystem, and the snapshot is
  always copied. If the `HasFS` instance is not provided, the `FsPath` path is
  interpreted relative to the session mount point, as before, and the snapshot
  is hard linked with a fallback to copying.

  Likewise, the type of `exportSnapshot` was changed from...

  ```hs
  exportSnapshot ::
    forall m h.
    (IOLike m) =>
    Session m ->
    SnapshotName ->
    FsPath ->
    m ()
  ```

  ...to...

  ```hs
  exportSnapshot ::
    forall m h.
    (IOLike m) =>
    Session m ->
    SnapshotName ->
    (Maybe (HasFS m h), FsPath) ->
    m ()
  ```

  The change in the type of the destination directory has the same
  interpretation as for `importSnapshot`.

### New features

#### Full API

* Add a new `importSnapshotIO` function that imports snapshots from disk using
  a `FilePath` path.

* Add a new `exportSnapshotIO` function that exports snapshots to disk using
  a `FilePath` path.

#### Simple API

* Add a new `importSnapshot` function that imports snapshots from disk using
  a `FilePath` path and a variant of `SnapshotImportDirDoesNotExistError` with
  a `FilePath` field.

* Add a new `exportSnapshot` function that exports snapshots to disk using
  a `FilePath` path and a variant of `SnapshotExportDirExistsError` with a
  `FilePath` field.

### Minor changes

* Revert the deprecation of `withOpenSessionIO`, since the other changes in this
  version have made it safe to use with `importSnapshot` and `exportSnapshot`.

### Bug fixes

* If an `SnapshotExportDirExistsError` is thrown, this now contains the
  destination directory, rather than the directory of the internap snapshot.

## 1.1.1.0 -- 2026-07-21

### Breaking changes

None

### New features

None

### Minor changes

* Support `data-elevator-0.3`. See [issue
  #856](https://github.com/IntersectMBO/lsm-tree/issues/856) and [PR
  #857](https://github.com/IntersectMBO/lsm-tree/pull/857).
* Support `ghc-9.14`. See [issue
  #813](https://github.com/IntersectMBO/lsm-tree/issues/813) and [PR
  #859](https://github.com/IntersectMBO/lsm-tree/pull/859).
* Drop support for `random < 1.2`. See [PR
  #865](https://github.com/IntersectMBO/lsm-tree/pull/865).

### Bug fixes

None

## 1.1.0.0 -- 2026-05-13

### Breaking changes

* Move to snapshot version v2 due to changes to the internal table
  representation. While this change is backwards compatible (i.e. new code
  is still able to read old snapshots), be aware that v2 snapshots cannot be
  read by older versions of `lsm-tree`.
  See [PR #834](https://github.com/IntersectMBO/lsm-tree/pull/834).

### New features

#### Full API

* Add a new `importSnapshot` function for importing snapshots from outside a
  session into that session. See [PR
  #835](https://github.com/IntersectMBO/lsm-tree/pull/835).
* Add a new `SnapshotImportDirDoesNotExistError` exception, which can currently
  only be thrown by thrown by `importSnapshot`. See [PR
  #835](https://github.com/IntersectMBO/lsm-tree/pull/835).
* Add a new `exportSnapshot` function for exporting snapshots from inside a
  session to outside that session. See [PR
  #835](https://github.com/IntersectMBO/lsm-tree/pull/835).
* Add a new `SnapshotExportDirExistsError` exception, which can currently only
  be thrown by thrown by `exportSnapshot`. See [PR
  #835](https://github.com/IntersectMBO/lsm-tree/pull/835).
* Add a new `withOpenMountedSessionIO` function, a variant of
  `withOpenSessionIO` with more general control over where snapshots can be
  exported to and imported from. See [PR
  #835](https://github.com/IntersectMBO/lsm-tree/pull/835).

### Minor changes

* Optimise internal structure of tables containing a completed union.
  See [PR #838](https://github.com/IntersectMBO/lsm-tree/pull/838).

#### Full API

* Deprecate `withOpenSessionIO` in favour of `withOpenMountedSessionIO`.
  `withOpenSessionIO` is generally unsafe to use with the new `importSnapshot`
  and `exportSnapshot` functions. See [PR
  #835](https://github.com/IntersectMBO/lsm-tree/pull/835).

### Bug fixes

None

## 1.0.0.2 -- 2026-04-24

### Breaking changes

None

### New features

None

### Minor changes

* Support `io-classes ^>=1.9` and `^>=1.10`. See [PR
  #819](https://github.com/IntersectMBO/lsm-tree/pull/819).
* Support `ghc-9.14`. See [PR
  #836](https://github.com/IntersectMBO/lsm-tree/pull/836).
* Support `containers-0.8`. See [PR
  #836](https://github.com/IntersectMBO/lsm-tree/pull/836).

### Bug fixes

* Fix a bug where `lookups` with a large number of input keys would sometimes
  return incorrect lookup results. See [PR
  #841](https://github.com/IntersectMBO/lsm-tree/pull/841).

## 1.0.0.1 -- 2025-12-03

* PATCH: support `filepath-1.4`. See PR
  [#804](https://github.com/IntersectMBO/lsm-tree/pull/804).

## 1.0.0.0 -- 2025-08-06

* First released version.
