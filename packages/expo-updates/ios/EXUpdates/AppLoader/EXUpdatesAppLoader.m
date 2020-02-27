//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesAppLoader+Private.h>
#import <EXUpdates/EXUpdatesDatabase.h>
#import <EXUpdates/EXUpdatesFileDownloader.h>
#import <EXUpdates/EXUpdatesUtils.h>
#import <UMCore/UMUtilities.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesAppLoader ()

@property (nonatomic, strong) NSMutableArray<EXUpdatesAsset *> *assetsToLoad;
@property (nonatomic, strong) NSMutableArray<EXUpdatesAsset *> *erroredAssets;
@property (nonatomic, strong) NSMutableArray<EXUpdatesAsset *> *finishedAssets;
@property (nonatomic, strong) NSMutableArray<EXUpdatesAsset *> *existingAssets;

@property (nonatomic, strong) NSLock *arrayLock;

@end

static NSString * const kEXUpdatesAppLoaderErrorDomain = @"EXUpdatesAppLoader";

@implementation EXUpdatesAppLoader

- (instancetype)init
{
  if (self = [super init]) {
    _assetsToLoad = [NSMutableArray new];
    _erroredAssets = [NSMutableArray new];
    _finishedAssets = [NSMutableArray new];
    _existingAssets = [NSMutableArray new];
    _arrayLock = [[NSLock alloc] init];
  }
  return self;
}

- (void)_reset
{
  _assetsToLoad = [NSMutableArray new];
  _erroredAssets = [NSMutableArray new];
  _finishedAssets = [NSMutableArray new];
  _existingAssets = [NSMutableArray new];
  _updateManifest = nil;
  _successBlock = nil;
  _errorBlock = nil;
}

# pragma mark - subclass methods

- (void)loadUpdateFromUrl:(NSURL *)url
                  success:(EXUpdatesAppLoaderSuccessBlock)success
                    error:(EXUpdatesAppLoaderErrorBlock)error
{
  @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Should not call EXUpdatesAppLoader#loadUpdate -- use a subclass instead" userInfo:nil];
}

- (void)downloadAsset:(EXUpdatesAsset *)asset
{
  @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Should not call EXUpdatesAppLoader#loadUpdate -- use a subclass instead" userInfo:nil];
}

# pragma mark - loading and database logic

- (void)startLoadingFromManifest:(EXUpdatesUpdate *)updateManifest
{
  if (![self _shouldStartLoadingUpdate:updateManifest]) {
    if (_successBlock) {
      _successBlock(nil);
    }
    return;
  }

  EXUpdatesDatabase *database = [EXUpdatesAppController sharedInstance].database;
  dispatch_async(database.databaseQueue, ^{
    NSError *existingUpdateError;
    EXUpdatesUpdate *existingUpdate = [database updateWithId:updateManifest.updateId error:&existingUpdateError];

    if (existingUpdate && existingUpdate.status == EXUpdatesUpdateStatusReady) {
      if (self->_successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          self->_successBlock(updateManifest);
        });
      }
      return;
    }

    if (existingUpdate) {
      // we've already partially downloaded the update.
      // however, it's not ready, so we should try to download all the assets again.
      self->_updateManifest = updateManifest;
    } else {
      if (existingUpdateError) {
        NSLog(@"Failed to select old update from DB: %@", existingUpdateError.localizedDescription);
      }
      // no update already exists with this ID, so we need to insert it and download everything.
      self->_updateManifest = updateManifest;
      NSError *updateError;
      [database addUpdate:self->_updateManifest error:&updateError];

      if (updateError) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          [self _finishWithError:updateError];
        });
        return;
      }
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      self->_assetsToLoad = [self->_updateManifest.assets mutableCopy];

      for (EXUpdatesAsset *asset in self->_updateManifest.assets) {
        [self downloadAsset:asset];
      }
    });
  });
}

- (void)handleAssetDownloadAlreadyExists:(EXUpdatesAsset *)asset
{
  [_arrayLock lock];
  [self->_assetsToLoad removeObject:asset];
  [self->_existingAssets addObject:asset];
  if (![self->_assetsToLoad count]) {
    [self _finish];
  }
  [_arrayLock unlock];
}

- (void)handleAssetDownloadWithError:(NSError *)error asset:(EXUpdatesAsset *)asset
{
  // TODO: retry. for now log an error
  NSLog(@"error loading file: %@: %@", asset.url.absoluteString, error.localizedDescription);
  [_arrayLock lock];
  [self->_assetsToLoad removeObject:asset];
  [self->_erroredAssets addObject:asset];
  if (![self->_assetsToLoad count]) {
    [self _finish];
  }
  [_arrayLock unlock];
}

- (void)handleAssetDownloadWithData:(NSData *)data response:(nullable NSURLResponse *)response asset:(EXUpdatesAsset *)asset
{
  [_arrayLock lock];
  [self->_assetsToLoad removeObject:asset];

  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    asset.headers = ((NSHTTPURLResponse *)response).allHeaderFields;
  }
  asset.contentHash = [EXUpdatesUtils sha256WithData:data];
  asset.downloadTime = [NSDate date];
  [self->_finishedAssets addObject:asset];

  if (![self->_assetsToLoad count]) {
    [self _finish];
  }
  [_arrayLock unlock];
}

# pragma mark - internal

- (BOOL)_shouldStartLoadingUpdate:(EXUpdatesUpdate *)updateManifest
{
  EXUpdatesAppController *controller = [EXUpdatesAppController sharedInstance];
  return [controller.selectionPolicy shouldLoadNewUpdate:updateManifest withLaunchedUpdate:controller.launchedUpdate];
}

- (void)_finishWithError:(NSError *)error
{
  if (_errorBlock) {
    _errorBlock(error);
  }
  [self _reset];
}

- (void)_finish
{
  EXUpdatesDatabase *database = [EXUpdatesAppController sharedInstance].database;
  dispatch_async(database.databaseQueue, ^{
    [self->_arrayLock lock];
    for (EXUpdatesAsset *existingAsset in self->_existingAssets) {
      NSError *error;
      BOOL existingAssetFound = [database addExistingAsset:existingAsset toUpdateWithId:self->_updateManifest.updateId error:&error];
      if (!existingAssetFound) {
        // the database and filesystem have gotten out of sync
        // do our best to create a new entry for this file even though it already existed on disk
        NSData *contents = [NSData dataWithContentsOfURL:[[EXUpdatesAppController sharedInstance].updatesDirectory URLByAppendingPathComponent:existingAsset.filename]];
        existingAsset.contentHash = [EXUpdatesUtils sha256WithData:contents];
        existingAsset.downloadTime = [NSDate date];
        [self->_finishedAssets addObject:existingAsset];
      }
      if (error) {
        NSLog(@"Error searching for existing asset in DB: %@", error.localizedDescription);
      }
    }
    NSError *assetError;
    [database addNewAssets:self->_finishedAssets toUpdateWithId:self->_updateManifest.updateId error:&assetError];
    if (assetError) {
      [self->_arrayLock unlock];
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self _finishWithError:assetError];
      });
      return;
    }

    if (![self->_erroredAssets count]) {
      NSError *updateReadyError;
      [database markUpdateReadyWithId:self->_updateManifest.updateId error:&updateReadyError];
      if (updateReadyError) {
        [self->_arrayLock unlock];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          [self _finishWithError:updateReadyError];
        });
        return;
      }
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      if (self->_erroredAssets.count) {
        if (self->_errorBlock) {
          self->_errorBlock([NSError errorWithDomain:kEXUpdatesAppLoaderErrorDomain
                                                code:1012
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load all assets"}]);
        }
      } else {
        if (self->_successBlock) {
          self->_successBlock(self->_updateManifest);
        }
      }

      [self->_arrayLock unlock];
      [self _reset];
    });
  });
}

@end

NS_ASSUME_NONNULL_END
