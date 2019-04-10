//
//  MWPhoto.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

//#import <SDWebImage/SDWebImageDecoder.h>
#import <SDWebImage/SDWebImageManager.h>
#import <SDWebImage/SDWebImageOperation.h>
#import <SDWebImage/SDWebImageTransition.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "MWPhoto.h"
#import "MWPhotoBrowser.h"

API_AVAILABLE(ios(8.0))
@interface MWPhoto () {

    BOOL _loadingInProgress;
//    id <SDWebImageOperation> _webImageOperation;
    PHImageRequestID _assetRequestID;
    PHImageRequestID _assetVideoRequestID;
        
}

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic) CGSize assetTargetSize;
@property (nonatomic, strong) id <SDWebImageOperation> webImageOperation;

- (void)imageLoadingComplete;

@end

@implementation MWPhoto

@synthesize underlyingImage = _underlyingImage; // synth property from protocol

#pragma mark - Class Methods

+ (MWPhoto *)photoWithImage:(UIImage *)image {
	return [[MWPhoto alloc] initWithImage:image];
}

+ (MWPhoto *)photoWithURL:(NSURL *)url {
    return [[MWPhoto alloc] initWithURL:url];
}

+ (MWPhoto *)photoWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize  API_AVAILABLE(ios(8.0)){
    return [[MWPhoto alloc] initWithAsset:asset targetSize:targetSize];
}

+ (MWPhoto *)videoWithURL:(NSURL *)url {
    return [[MWPhoto alloc] initWithVideoURL:url];
}

#pragma mark - Init

- (id)init {
    if ((self = [super init])) {
        self.emptyImage = YES;
        [self setup];
    }
    return self;
}

- (id)initWithImage:(UIImage *)image {
    if ((self = [super init])) {
        self.image = image;
        [self setup];
    }
    return self;
}

- (id)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.photoURL = url;
        [self setup];
    }
    return self;
}

- (id)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize  API_AVAILABLE(ios(8.0)){
    if ((self = [super init])) {
        self.asset = asset;
        self.assetTargetSize = targetSize;
        if (@available(iOS 8.0, *)) {
            self.isVideo = asset.mediaType == PHAssetMediaTypeVideo;
        } else {
            // Fallback on earlier versions
        }
        [self setup];
    }
    return self;
}

- (id)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        self.videoURL = url;
        self.isVideo = YES;
        self.emptyImage = YES;
        [self setup];
    }
    return self;
}

- (void)setup {
    _assetRequestID = PHInvalidImageRequestID;
    _assetVideoRequestID = PHInvalidImageRequestID;
}

- (void)dealloc {
    [self cancelAnyLoading];
}

#pragma mark - Video

- (void)setVideoURL:(NSURL *)videoURL {
    _videoURL = videoURL;
    self.isVideo = YES;
}

- (void)getVideoURL:(void (^)(NSURL *url))completion {
    if (_videoURL) {
        completion(_videoURL);
    } else if (@available(iOS 8.0, *)) {
        if (_asset && _asset.mediaType == PHAssetMediaTypeVideo) {
            [self cancelVideoRequest]; // Cancel any existing
            PHVideoRequestOptions *options = [PHVideoRequestOptions new];
            options.networkAccessAllowed = YES;
            typeof(self) __weak weakSelf = self;
            _assetVideoRequestID = [[PHImageManager defaultManager] requestAVAssetForVideo:_asset options:options resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info) {
                
                // dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ // Testing
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf->_assetVideoRequestID = PHInvalidImageRequestID;
                if ([asset isKindOfClass:[AVURLAsset class]]) {
                    completion(((AVURLAsset *)asset).URL);
                } else {
                    completion(nil);
                }
                
            }];
        }
    } else {
        // Fallback on earlier versions
    }
}

#pragma mark - MWPhoto Protocol Methods

- (UIImage *)underlyingImage {
    return _underlyingImage;
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    @try {
        if (self.underlyingImage) {
            [self imageLoadingComplete];
        } else {
            [self performLoadUnderlyingImageAndNotify];
        }
    }
    @catch (NSException *exception) {
        self.underlyingImage = nil;
        _loadingInProgress = NO;
        [self imageLoadingComplete];
    }
    @finally {
    }
}

// Set the underlyingImage
- (void)performLoadUnderlyingImageAndNotify {
    
    // Get underlying image
    if (_image) {
        
        // We have UIImage!
        self.underlyingImage = _image;
        [self imageLoadingComplete];
        
    } else if (_photoURL) {
        
        // Check what type of url it is
        if ([[[_photoURL scheme] lowercaseString] isEqualToString:@"assets-library"]) {
            
            // Load from assets library
            [self _performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL: _photoURL];
            
        } else if ([_photoURL isFileReferenceURL]) {
            
            // Load from local file async
            [self _performLoadUnderlyingImageAndNotifyWithLocalFileURL: _photoURL];
            
        } else {
            
            // Load async from web (using SDWebImage)
            [self _performLoadUnderlyingImageAndNotifyWithWebURL: _photoURL];
            
        }
        
    } else if (_asset) {
        
        // Load from photos asset
        [self _performLoadUnderlyingImageAndNotifyWithAsset: _asset targetSize:_assetTargetSize];
        
    } else {
        
        // Image is empty
        [self imageLoadingComplete];
        
    }
}

// Load from local file
- (void)_performLoadUnderlyingImageAndNotifyWithWebURL:(NSURL *)url {
    @try {
        NSString* urlString = [url absoluteString];
        if ([urlString hasPrefix:@"thumb"]) {
            urlString = [urlString substringFromIndex:5];
            NSLog(@"-- %@",urlString);
            url = [NSURL URLWithString:urlString];
        }
        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        __weak typeof(self) weakSelf = self;
        _webImageOperation = [manager loadImageWithURL:url options:0 progress:^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
            if (expectedSize > 0) {
                float progress = receivedSize / (float)expectedSize;
                NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithFloat:progress], @"progress",
                                      self, @"photo", nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
            }
        } completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
            if (error) {
                MWLog(@"SDWebImage failed to download image: %@", error);
            }
            weakSelf.webImageOperation = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf imageLoadingComplete];
            });
        }];
//        _webImageOperation = [manager downloadImageWithURL:url
//                                                   options:0
//                                                  progress:^(NSInteger receivedSize, NSInteger expectedSize) {
//                                                      if (expectedSize > 0) {
//                                                          float progress = receivedSize / (float)expectedSize;
//                                                          NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
//                                                                                [NSNumber numberWithFloat:progress], @"progress",
//                                                                                self, @"photo", nil];
//                                                          [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
//                                                      }
//                                                  }
//                                                 completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
    } @catch (NSException *e) {
        MWLog(@"Photo from web: %@", e);
        _webImageOperation = nil;
        [self imageLoadingComplete];
    }
}

// Load from local file
- (void)_performLoadUnderlyingImageAndNotifyWithLocalFileURL:(NSURL *)url {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @try {
                self.underlyingImage = [UIImage imageWithContentsOfFile:url.path];
                if (!self.underlyingImage) {
                    MWLog(@"Error loading photo from path: %@", url.path);
                }
            } @finally {
                [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
            }
        }
    });
}

// Load from asset library async
- (void)_performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL:(NSURL *)url {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @try {
                ALAssetsLibrary *assetslibrary = [[ALAssetsLibrary alloc] init];
                [assetslibrary assetForURL:url
                               resultBlock:^(ALAsset *asset){
                                   ALAssetRepresentation *rep = [asset defaultRepresentation];
                                   CGImageRef iref = [rep fullScreenImage];
                                   if (iref) {
                                       self.underlyingImage = [UIImage imageWithCGImage:iref];
                                   }
                                   [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                               }
                              failureBlock:^(NSError *error) {
                                  self.underlyingImage = nil;
                                  MWLog(@"Photo from asset library error: %@",error);
                                  [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
                              }];
            } @catch (NSException *e) {
                MWLog(@"Photo from asset library error: %@", e);
                [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
            }
        }
    });
}

// Load from photos library
- (void)_performLoadUnderlyingImageAndNotifyWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize  API_AVAILABLE(ios(8.0)){
    
    if (@available(iOS 8.0, *)) {
        PHImageManager *imageManager = [PHImageManager defaultManager];
        
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        options.networkAccessAllowed = YES;
        options.resizeMode = PHImageRequestOptionsResizeModeFast;
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        options.synchronous = false;
        options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
            NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithDouble: progress], @"progress",
                                  self, @"photo", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
        };
        
        _assetRequestID = [imageManager requestImageForAsset:asset targetSize:targetSize contentMode:PHImageContentModeAspectFit options:options resultHandler:^(UIImage *result, NSDictionary *info) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.underlyingImage = result;
                [self imageLoadingComplete];
            });
        }];
    } else {
        // Fallback on earlier versions
    }if (@available(iOS 8.0, *)) {
        PHImageManager *imageManager = [PHImageManager defaultManager];
    } else {
        // Fallback on earlier versions
    }

}

// Release if we can get it again from path or url
- (void)unloadUnderlyingImage {
    _loadingInProgress = NO;
	self.underlyingImage = nil;
}

- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    // Notify on next run loop
    [self performSelector:@selector(postCompleteNotification) withObject:nil afterDelay:0];
}

- (void)postCompleteNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

- (void)cancelAnyLoading {
    if (_webImageOperation != nil) {
        [_webImageOperation cancel];
        _loadingInProgress = NO;
    }
    [self cancelImageRequest];
    [self cancelVideoRequest];
}

- (void)cancelImageRequest {
    if (_assetRequestID != PHInvalidImageRequestID) {
        if (@available(iOS 8.0, *)) {
            [[PHImageManager defaultManager] cancelImageRequest:_assetRequestID];
        } else {
            // Fallback on earlier versions
        }
        _assetRequestID = PHInvalidImageRequestID;
    }
}

- (void)cancelVideoRequest {
    if (_assetVideoRequestID != PHInvalidImageRequestID) {
        if (@available(iOS 8.0, *)) {
            [[PHImageManager defaultManager] cancelImageRequest:_assetVideoRequestID];
        } else {
            // Fallback on earlier versions
        }
        _assetVideoRequestID = PHInvalidImageRequestID;
    }
}

@end
