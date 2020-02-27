//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesRemoteAppLoader.h>
#import <EXUpdates/EXUpdatesCrypto.h>
#import <EXUpdates/EXUpdatesFileDownloader.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesRemoteAppLoader ()

@property (nonatomic, strong) EXUpdatesFileDownloader *downloader;

@end

@implementation EXUpdatesRemoteAppLoader

- (instancetype)init
{
  if (self = [super init]) {
    _downloader = [[EXUpdatesFileDownloader alloc] init];
  }
  return self;
}

- (void)loadUpdateFromUrl:(NSURL *)url
                  success:(EXUpdatesAppLoaderSuccessBlock)success
                    error:(EXUpdatesAppLoaderErrorBlock)error
{
  self.successBlock = success;
  self.errorBlock = error;
  [_downloader downloadManifestFromURL:url successBlock:^(EXUpdatesUpdate *update) {
    [self startLoadingFromManifest:update];
  } errorBlock:^(NSError *error, NSURLResponse *response) {
    if (self.errorBlock) {
      self.errorBlock(error);
    }
  }];
}

- (void)downloadAsset:(EXUpdatesAsset *)asset
{
  NSURL *updatesDirectory = [EXUpdatesAppController sharedInstance].updatesDirectory;
  NSURL *urlOnDisk = [updatesDirectory URLByAppendingPathComponent:asset.filename];
  if ([[NSFileManager defaultManager] fileExistsAtPath:[urlOnDisk path]]) {
    // file already exists, we don't need to download it again
    [self handleAssetDownloadAlreadyExists:asset];
  } else {
    [_downloader downloadFileFromURL:asset.url toPath:[urlOnDisk path] successBlock:^(NSData *data, NSURLResponse *response) {
      [self handleAssetDownloadWithData:data response:response asset:asset];
    } errorBlock:^(NSError *error, NSURLResponse *response) {
      [self handleAssetDownloadWithError:error asset:asset];
    }];
  }
}

@end

NS_ASSUME_NONNULL_END
