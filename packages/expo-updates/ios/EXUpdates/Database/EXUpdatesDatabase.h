//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAsset.h>
#import <EXUpdates/EXUpdatesUpdate.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EXUpdatesDatabaseHashType) {
  EXUpdatesDatabaseHashTypeSha1 = 0
};

@interface EXUpdatesDatabase : NSObject

@property (nonatomic, strong) dispatch_queue_t databaseQueue;

- (BOOL)openDatabaseWithError:(NSError ** _Nullable)error;
- (void)closeDatabase;

- (void)addUpdate:(EXUpdatesUpdate *)update error:(NSError ** _Nullable)error;
- (void)addNewAssets:(NSArray<EXUpdatesAsset *> *)assets toUpdateWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error;
- (BOOL)addExistingAsset:(EXUpdatesAsset *)asset toUpdateWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error;
- (void)updateAsset:(EXUpdatesAsset *)asset error:(NSError ** _Nullable)error;
- (void)markUpdateReadyWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error;

- (void)markUpdateForDeletionWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error;
- (nullable NSArray<NSDictionary *> *)markUnusedAssetsForDeletionWithError:(NSError ** _Nullable)error;
- (void)deleteAssetsWithIds:(NSArray<NSNumber *> *)assetIds error:(NSError ** _Nullable)error;
- (void)deleteUnusedUpdatesWithError:(NSError ** _Nullable)error;

- (nullable NSArray<EXUpdatesUpdate *> *)allUpdatesWithError:(NSError ** _Nullable)error;
- (nullable NSArray<EXUpdatesUpdate *> *)launchableUpdatesWithError:(NSError ** _Nullable)error;
- (nullable EXUpdatesUpdate *)updateWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error;
- (nullable EXUpdatesAsset *)launchAssetWithUpdateId:(NSUUID *)updateId error:(NSError ** _Nullable)error;
- (nullable NSArray<EXUpdatesAsset *> *)assetsWithUpdateId:(NSUUID *)updateId error:(NSError ** _Nullable)error;

@end

NS_ASSUME_NONNULL_END
