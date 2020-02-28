//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesDatabase.h>
#import <EXUpdates/EXUpdatesReaper.h>

NS_ASSUME_NONNULL_BEGIN

@implementation EXUpdatesReaper

+ (void)reapUnusedUpdatesWithSelectionPolicy:(id<EXUpdatesSelectionPolicy>)selectionPolicy
                              launchedUpdate:(EXUpdatesUpdate *)launchedUpdate
{
  EXUpdatesDatabase *database = [EXUpdatesAppController sharedInstance].database;
  dispatch_async(database.databaseQueue, ^{
    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *updatesDirectory = [EXUpdatesAppController sharedInstance].updatesDirectory;

    NSDate *beginMarkForDeletion = [NSDate date];
    [database markUpdateReadyWithId:launchedUpdate.updateId error:&error];
    if (error) {
      NSLog(@"Error reaping updates: %@", error.localizedDescription);
      return;
    }

    NSArray<EXUpdatesUpdate *> *allUpdates = [database allUpdatesWithError:&error];
    if (!allUpdates || error) {
      NSLog(@"Error reaping updates: %@", error.localizedDescription);
      return;
    }
    NSArray<EXUpdatesUpdate *> *updatesToDelete = [selectionPolicy updatesToDeleteWithLaunchedUpdate:launchedUpdate updates:allUpdates];
    for (EXUpdatesUpdate *update in updatesToDelete) {
      [database markUpdateForDeletionWithId:update.updateId error:&error];
      if (error) {
        NSLog(@"Error reaping updates: %@", error.localizedDescription);
        return;
      }
    }
    NSArray<NSDictionary *> *assetsForDeletion = [database markUnusedAssetsForDeletionWithError:&error];
    if (error) {
      NSLog(@"Error reaping updates: %@", error.localizedDescription);
      return;
    }
    NSLog(@"Marked updates and assets for deletion in %f ms", [beginMarkForDeletion timeIntervalSinceNow] * -1000);

    NSMutableArray<NSNumber *> *deletedAssets = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *erroredAssets = [NSMutableArray new];

    dispatch_sync(EXUpdatesAppController.sharedInstance.assetFilesQueue, ^{
      NSDate *beginDeleteAssets = [NSDate date];
      for (NSDictionary *asset in assetsForDeletion) {
        NSAssert([@(1) isEqualToNumber:asset[@"marked_for_deletion"]], @"asset should be marked for deletion");
        NSNumber *assetId = asset[@"id"];
        NSString *relativePath = asset[@"relative_path"];
        NSAssert([assetId isKindOfClass:[NSNumber class]], @"asset id should be a nonnull number");
        NSAssert([relativePath isKindOfClass:[NSString class]], @"relative_path should be a nonnull string");

        NSURL *fileUrl = [updatesDirectory URLByAppendingPathComponent:relativePath];
        NSError *err;
        if (![fileManager fileExistsAtPath:fileUrl.path] || [fileManager removeItemAtURL:fileUrl error:&err]) {
          [deletedAssets addObject:assetId];
        } else {
          [erroredAssets addObject:asset];
          NSLog(@"Error deleting asset at %@: %@", fileUrl, [err localizedDescription]);
        }
      }
      NSLog(@"Deleted %lu assets from disk in %f ms", (unsigned long)[deletedAssets count], [beginDeleteAssets timeIntervalSinceNow] * -1000);

      NSDate *beginRetryDeletes = [NSDate date];
      // retry errored deletions
      for (NSDictionary *asset in erroredAssets) {
        NSNumber *assetId = asset[@"id"];
        NSString *relativePath = asset[@"relative_path"];

        NSURL *fileUrl = [updatesDirectory URLByAppendingPathComponent:relativePath];
        NSError *err;
        if (![fileManager fileExistsAtPath:fileUrl.path] || [fileManager removeItemAtURL:fileUrl error:&err]) {
          [deletedAssets addObject:assetId];
          [erroredAssets removeObject:asset];
        } else {
          NSLog(@"Retried deleting asset at %@ and failed again: %@", fileUrl, [err localizedDescription]);
        }
      }
      NSLog(@"Retried deleting assets from disk in %f ms", [beginRetryDeletes timeIntervalSinceNow] * -1000);
    });

    NSDate *beginDeleteFromDatabase = [NSDate date];
    NSError *deleteAssetsError;
    NSError *deleteUpdatesError;
    [database deleteAssetsWithIds:deletedAssets error:&deleteAssetsError];
    [database deleteUnusedUpdatesWithError:&deleteUpdatesError];
    NSAssert(!deleteAssetsError && !deleteUpdatesError, @"Inconsistent state; error removing deleted updates or assets from DB");
    NSLog(@"Deleted assets and updates from SQLite in %f ms", [beginDeleteFromDatabase timeIntervalSinceNow] * -1000);
  });
}

@end

NS_ASSUME_NONNULL_END
