//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesConfig.h>
#import <EXUpdates/EXUpdatesDatabase.h>
#import <EXUpdates/EXUpdatesUpdate+Private.h>
#import <EXUpdates/EXUpdatesUpdateLegacy.h>
#import <EXUpdates/EXUpdatesUpdateNew.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesUpdate ()

@property (nonatomic, strong, readwrite) NSDictionary *rawManifest;

@end

@implementation EXUpdatesUpdate

- (instancetype)initWithRawManifest:(NSDictionary *)manifest
{
  if (self = [super init]) {
    _rawManifest = manifest;
  }
  return self;
}

+ (instancetype)updateWithId:(NSUUID *)updateId
    commitTime:(NSDate *)commitTime
runtimeVersion:(NSString *)runtimeVersion
      metadata:(NSDictionary * _Nullable)metadata
        status:(EXUpdatesUpdateStatus)status
          keep:(BOOL)keep
{
  // for now, we store the entire managed manifest in the metadata field
  EXUpdatesUpdate *update = [[self alloc] initWithRawManifest:metadata];
  update.updateId = updateId;
  update.commitTime = commitTime;
  update.runtimeVersion = runtimeVersion;
  update.metadata = metadata;
  update.status = status;
  update.keep = keep;
  return update;
}

+ (instancetype)updateWithManifest:(NSDictionary *)manifest
{
  if ([EXUpdatesConfig sharedInstance].usesLegacyManifest) {
    return [EXUpdatesUpdateLegacy updateWithLegacyManifest:manifest];
  } else {
    return [EXUpdatesUpdateNew updateWithNewManifest:manifest];
  }
}

- (NSArray<EXUpdatesAsset *>*)assets
{
  if (!_assets) {
    EXUpdatesDatabase *db = [EXUpdatesAppController sharedInstance].database;
    NSError *error;
    _assets = [db assetsWithUpdateId:_updateId error:&error];
    NSAssert(_assets, @"Assets should be nonnull when selected from DB: %@", error.localizedDescription);
  }
  return _assets;
}

@end

NS_ASSUME_NONNULL_END
