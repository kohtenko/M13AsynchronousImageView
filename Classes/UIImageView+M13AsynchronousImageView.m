//
//  UIImageView+M13AsynchronousImageView.m
//  M13AsynchronousImageView
//
//  Created by Brandon McQuilkin on 4/24/14.
//  Copyright (c) 2014 Brandon McQuilkin. All rights reserved.
//

#import "UIImageView+M13AsynchronousImageView.h"

/**
 The base class that outlines the interface for loading image files.
 */
@interface M13AsynchronousImageLoaderConnection : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>

/**
 The NSData of downloaded image.
 */
@property (nonatomic, strong) NSMutableData *imageData;
/**
 The URL of the file to load.
 */
@property (nonatomic, strong) NSURL *fileURL;
/**
 The target of the image loading.
 */
@property (nonatomic, strong) id target;
/**
 The duration of time to wait for a timeout.
 */
@property (nonatomic, assign) NSTimeInterval timeoutInterval;
/**
 The completion block to run once the image is downloaded.
 */
@property (nonatomic, copy) M13AsynchronousImageLoaderCompletionBlock completionBlock;
/**
 *  array of completion blocks associated with one connection
 */
@property (nonatomic, strong) NSMutableArray *completionBlocks;
/**
 Loads image into memory in background thread.
 
 @param image UIImage object loaded with NSData or from filePath.
 @param completionBlock The completion block of image loading into memory.
 */
+ (void)forceImageToDescompress:(UIImage *)image completionHandler:(void(^)(UIImage * image))handler;
/**
 The completion block to run once the image has loaded.
 
 @param completionBlock The completion block to run.
 */
- (void)setCompletionBlock:(M13AsynchronousImageLoaderCompletionBlock)completionBlock;

/**
 Begin loading the image.
 */
- (void)startLoading;
/**
 Cancel loading the image.
 */
- (void)cancelLoading;
/**
 Wether or not the loader is currently loading the image.
 
 @return Wether or not the loader is currently loading the image.
 */
- (BOOL)isLoading;
/**
 Wether or not the loader completed loading the image.
 
 @return Wether or not the loader completed loading the image.
 */
- (BOOL)finishedLoading;

@end


@interface M13AsynchronousImageLoader ()
/**
 The queue of connections to load image files.
 */
@property (nonatomic, strong) NSMutableArray *connectionQueue;
/**
 The list of active connections.
 */
@property (nonatomic, strong) NSMutableArray *activeConnections;

@end

@implementation M13AsynchronousImageLoader

+ (M13AsynchronousImageLoader *)defaultLoader
{
    return [M13AsynchronousImageLoader loaderWithName:@"Default"];
}

+ (M13AsynchronousImageLoader *)loaderWithName:(NSString *)name
{
    return [M13AsynchronousImageLoader loaderWithName:name cleanup:NO];
}

+ (void)cleanupLoaderWithName:(NSString *)name
{
    [M13AsynchronousImageLoader loaderWithName:name cleanup:YES];
}

+ (M13AsynchronousImageLoader *)loaderWithName:(NSString *)name cleanup:(BOOL)cleanup
{
    //Create the dictionary to hold the loader if necessary
    static dispatch_once_t onceToken;
    static NSMutableDictionary *loaders;
    dispatch_once(&onceToken, ^{
        loaders = [[NSMutableDictionary alloc] init];
    });
    
    //Create or Cleanup?
    if (!cleanup) {
        //Create / retreive
        if (!loaders[name]) {
            [loaders setObject:[[M13AsynchronousImageLoader alloc] init] forKey:name];
        }
        
        return loaders[name];
    } else {
        //Remove
        [loaders removeObjectForKey:name];
    }
    
    return nil;
}

- (id)init
{
    self = [super init];
    if (self) {
        _imageCache = [M13AsynchronousImageLoader defaultImageCache];
        _maximumNumberOfConcurrentLoads = 5;
        _loadingTimeout = 30.0;
        _connectionQueue = [NSMutableArray array];
        _activeConnections = [NSMutableArray array];
    }
    return self;
}

+ (NSCache *)defaultImageCache
{
    static dispatch_once_t onceToken;
    static NSCache *defaultCache;
    dispatch_once(&onceToken, ^{
        defaultCache = [[NSCache alloc] init];
    });
    return defaultCache;
}

- (void)loadImageAtURL:(NSURL *)url
{
    [self loadImageAtURL:url target:nil completion:nil];
}
- (void)loadImageAtURL:(NSURL *)url target:(id)target completion:(M13AsynchronousImageLoaderCompletionBlock)completion
{
    [self loadImageAtURL:url fileURL:nil target:target completion:completion];
}

- (void)loadImageAtURL:(NSURL *)url fileURL:(NSURL *)fileURL target:(id)target completion:(M13AsynchronousImageLoaderCompletionBlock)completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //Try loading the image from the cache first.
        UIImage *image = [self.imageCache objectForKey:url];
        //If we have the image, return
        if (image) {
            if (completion)
                completion(YES, M13AsynchronousImageLoaderImageLoadedLocationCache, image, url, target, nil);
            return;
        }
        
        //Try loading the image from the fileURL second.
        image = [UIImage imageWithContentsOfFile:fileURL.path];
        if (image) {
            [M13AsynchronousImageLoaderConnection forceImageToDescompress:image completionHandler:^(UIImage *image) {
                [self.imageCache setObject:image forKey:url];
                if (completion)
                    completion(YES, M13AsynchronousImageLoaderImageLoadedLocationLocalFile, image, url, target, nil);
            }];
            return;
        }
        
        M13AsynchronousImageLoaderCompletionBlock block = ^(BOOL success, M13AsynchronousImageLoaderImageLoadedLocation location, UIImage *image, NSURL *url, id target, NSData *imageData) {
            //Add the image to the cache
            if (success) {
                [self.imageCache setObject:image forKey:url];
                if (fileURL) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [imageData writeToURL:fileURL atomically:YES];
                    });
                }
            }
            
            //Run the completion block
            if (completion)
                completion(success, location, image, url, target, imageData);
            
            //Update the connections
            [self updateConnections];
        };
        
        for (M13AsynchronousImageLoaderConnection *connection in _connectionQueue) {
            if ([connection.fileURL isEqual:url]) {
                [connection setCompletionBlock:block];
                return;
            }
        }
        
        
        //Not in cache, load the image.
        M13AsynchronousImageLoaderConnection *connection = [[M13AsynchronousImageLoaderConnection alloc] init];
        connection.fileURL = url;
        connection.target = target;
        connection.timeoutInterval = _loadingTimeout;
        [connection setCompletionBlock:block];
        
        //Add the connection to the queue
        [_connectionQueue addObject:connection];
        //Update the connections
        [self updateConnections];
        
    });
}


- (void)updateConnections
{
    //First check if any of the active connections are finished.
    NSMutableArray *completedConnections = [NSMutableArray array];
    for (M13AsynchronousImageLoaderConnection *connection in _activeConnections) {
        if (connection.finishedLoading) {
            [completedConnections addObject:connection];
        }
    }
    //Remove the completed connections
    [_activeConnections removeObjectsInArray:completedConnections];
    [_connectionQueue removeObjectsInArray:completedConnections];
    
    //Check our queue to see if a completed connection loaded an image a connection in the queue is requesting. If so, mark it as completed, and remove it from the queue
    NSMutableArray *completedByProxyConnections = [NSMutableArray array];
    for (M13AsynchronousImageLoaderConnection *queuedConnection in _connectionQueue) {
        for (M13AsynchronousImageLoaderConnection *completedConnection in completedConnections) {
            if ([queuedConnection.fileURL isEqual:completedConnection.fileURL]) {
                //Run the queued connection's completion, and add to the array for removal
                [completedByProxyConnections addObject:queuedConnection];
                //Figure out where the file was loaded from. Don't want to use cache, since this was a loaded image.
                M13AsynchronousImageLoaderImageLoadedLocation location = [queuedConnection.fileURL isFileURL] ? M13AsynchronousImageLoaderImageLoadedLocationLocalFile : M13AsynchronousImageLoaderImageLoadedLocationExternalFile;
                //Run the completion.
                M13AsynchronousImageLoaderCompletionBlock completion = queuedConnection.completionBlock;
                UIImage *image = [self.imageCache objectForKey:queuedConnection.fileURL];
                completion(image != nil, location, image, queuedConnection.fileURL, queuedConnection.target, queuedConnection.imageData);
            }
        }
    }
    
    //Remove the completed connections
    [_connectionQueue removeObject:completedByProxyConnections];
    
    //Now start new connections, until we reach the maximum concurrent connections amount.
    for (int i = 0; i < _maximumNumberOfConcurrentLoads - _activeConnections.count; i++) {
        if (i < _connectionQueue.count) {
            M13AsynchronousImageLoaderConnection *connection = _connectionQueue[i];
            //Start the connection
            [connection startLoading];
            [_activeConnections addObject:connection];
        }
    }
}

- (void)cancelLoadingImageAtURL:(NSURL *)url
{
    [self cancelLoadingImageWithBlock:^BOOL(NSURL *_url, id _target) {
        return [url isEqual:_url];
    }];
}

- (void)cancelLoadingImagesForTarget:(id)target
{
    [self cancelLoadingImageWithBlock:^BOOL(NSURL *_url, id _target) {
        return target == _target;
    }];
}

- (void)cancelLoadingImageAtURL:(NSURL *)url target:(id)target
{
    [self cancelLoadingImageWithBlock:^BOOL(NSURL *_url, id _target) {
        return target == _target && [url isEqual:_url];
    }];
}

- (void)cancelLoadingImageWithBlock:(BOOL (^) (NSURL *_url, id _target))statementBlock {
    NSMutableArray *objectsToRemove = [NSMutableArray array];
    //Cancel connections when statementBlock returns YES
    for (M13AsynchronousImageLoaderConnection *connection in _connectionQueue) {
        if (statementBlock(connection.fileURL, connection.target)) {
            [connection cancelLoading];
            [objectsToRemove addObject:connection];
        }
    }
    //Remove those connections from the list.
    [_connectionQueue removeObjectsInArray:objectsToRemove];
    [_activeConnections removeObjectsInArray:objectsToRemove];
    [self updateConnections];
}


@end

@implementation M13AsynchronousImageLoaderConnection
{
    BOOL loading;
    BOOL receivedData;
    BOOL finished;
    BOOL canceled;
    NSURLConnection *imageConnection;
}

+ (void)forceImageToDescompress:(UIImage *)image completionHandler:(void(^)(UIImage * image))handler{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (image) {
            CGImageRef imageRef = image.CGImage;
            // System only supports RGB, set explicitly and prevent context error
            // if the downloaded image is not the supported format
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(NULL,
                                                         CGImageGetWidth(imageRef),
                                                         CGImageGetHeight(imageRef),
                                                         8,
                                                         // width * 4 will be enough because are in ARGB format, don't read from the image
                                                         CGImageGetWidth(imageRef) * 4,
                                                         colorSpace,
                                                         // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
                                                         // makes system don't need to do extra conversion when displayed.
                                                         kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            CGColorSpaceRelease(colorSpace);
            if ( ! context) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(nil);
                });
            }
            CGRect rect = (CGRect){CGPointZero, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef)};
            CGContextDrawImage(context, rect, imageRef);
            CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
            UIImage *imageObject = [[UIImage alloc] initWithCGImage:decompressedImageRef];
            CGImageRelease(decompressedImageRef);
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(imageObject);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(nil);
            });
        }
    });
}

- (void)setCompletionBlock:(M13AsynchronousImageLoaderCompletionBlock)completionBlock
{
    if (!self.completionBlocks){
        self.completionBlocks = [NSMutableArray array];
        __weak M13AsynchronousImageLoaderConnection *weakSelf = self;
        _completionBlock = ^(BOOL success, M13AsynchronousImageLoaderImageLoadedLocation location, UIImage *image, NSURL *url, id target, NSData *imageData) {
            for (M13AsynchronousImageLoaderCompletionBlock block in weakSelf.completionBlocks) {
                block(success, location, image, url, target, imageData);
            }
        };
    }
    [self.completionBlocks addObject:completionBlock];
}

- (void)startLoading
{
    //If we are loading, or have finished, return
    if (loading || finished) {
        return;
    }
    
    //Check to see if our URL is != nil
    if (_fileURL == nil) {
        //Fail
        finished = YES;
        _completionBlock(NO, M13AsynchronousImageLoaderImageLoadedLocationNone, nil, nil, _target, nil);
        return;
    }
    
    //Begin loading
    loading = YES;
    
    if ([_fileURL isFileURL]) {
        NSData *data = [NSData dataWithContentsOfURL:_fileURL];
        UIImage *image = [UIImage imageWithData:data];
        [M13AsynchronousImageLoaderConnection forceImageToDescompress:image completionHandler:^(UIImage *image) {
            finished = YES;
            loading = NO;
            if (image)
                _completionBlock(YES, M13AsynchronousImageLoaderImageLoadedLocationExternalFile, image, _fileURL, _target, data);
            else
                _completionBlock(NO, M13AsynchronousImageLoaderImageLoadedLocationLocalFile, nil, _fileURL, _target, data);
        }];
    } else {
        //Our URL is to an external file, No caching, we do that ourselves.
        NSURLRequest *request = [NSURLRequest requestWithURL:_fileURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:_timeoutInterval];
        //Create a connection
        imageConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        [imageConnection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        //Start the connection
        [imageConnection start];
    }
}

- (void)cancelLoading
{
    canceled = YES;
    
    //Check to see if we are doing anything.
    if (!loading) {
        //Doing nothing, nothing to clean up.
        finished = YES;
        return;
    }
    
    //Clean up
    loading = NO;
    finished = YES;
    [imageConnection cancel];
    imageConnection = nil;
    self.imageData = nil;
}

- (BOOL)isLoading
{
    return loading;
}

- (BOOL)finishedLoading
{
    return finished;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    //Setup to collect image data
    self.imageData = [NSMutableData data];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    //Add the received data to the image data
    receivedData = YES;
    [self.imageData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    //Connection failed, failed to load image.
    self.imageData = nil;
    imageConnection = nil;
    
    finished = YES;
    loading = NO;
    
    NSLog(@"Failed To Load Image: %@", error.localizedDescription);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _completionBlock(NO, M13AsynchronousImageLoaderImageLoadedLocationExternalFile, nil, _fileURL, _target, nil);
    });
    
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    //Canceled, no need to process image.
    if (canceled) {
        self.imageData = nil;
        [imageConnection cancel];
        imageConnection = nil;
        return;
    }
    
    if (receivedData) {
        //Still need to work in the background, not the main thread
        UIImage *image = [UIImage imageWithData:self.imageData];
        imageConnection = nil;
        [M13AsynchronousImageLoaderConnection forceImageToDescompress:image completionHandler:^(UIImage *image) {
            finished = YES;
            loading = NO;
            _completionBlock(image != nil, M13AsynchronousImageLoaderImageLoadedLocationExternalFile, image, _fileURL, _target, self.imageData);
            self.imageData = nil;
        }];
    }
}

@end

@implementation UIImageView (M13AsynchronousImageView)


+ (void)setCacheLimit:(NSUInteger)cacheLimit{
    [M13AsynchronousImageLoader defaultLoader].imageCache.countLimit = cacheLimit;
}

- (void)loadImageFromCachePath:(NSString *)path{
    [self loadImageFromCachePath:path completion:nil];
}

- (void)loadImageFromCachePath:(NSString *)path completion:(M13AsynchronousImageLoaderCompletionBlock)completion{
    NSURL *url = [[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:path];
    [self loadImageFromURL:url completion:completion];
}

- (void)loadImageFromDocumentPath:(NSString *)path{
    [self loadImageFromDocumentPath:path completion:nil];
}

- (void)loadImageFromDocumentPath:(NSString *)path completion:(M13AsynchronousImageLoaderCompletionBlock)completion{
    NSURL *url = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:path];
    [self loadImageFromURL:url completion:completion];
}

- (void)loadImageFromURL:(NSURL *)url
{
    [self loadImageFromURL:url completion:nil];
}
- (void)loadImageFromURL:(NSURL *)url toFileURL:(NSURL *)fileURL
{
    [self loadImageFromURL:url toFileURL:fileURL completion:nil];
}
- (void)loadImageFromURL:(NSURL *)url completion:(M13AsynchronousImageLoaderCompletionBlock)completion
{
    [self loadImageFromURL:url toFileURL:nil completion:completion];
}

- (void)loadImageFromURL:(NSURL *)url toFileURL:(NSURL *)fileURL completion:(M13AsynchronousImageLoaderCompletionBlock)completion
{
    self.image = nil;
    [[M13AsynchronousImageLoader defaultLoader] loadImageAtURL:url fileURL:fileURL target:self completion:^(BOOL success, M13AsynchronousImageLoaderImageLoadedLocation location, UIImage *image, NSURL *url, id target, NSData* imageData) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            //Set the image if loaded
            if (success) {
                self.image = image;
            }
            //Run the completion
            if (completion){
                completion(success, location, image, url, target, imageData);
            }
        });
    }];
}

- (void)cancelLoadingAllImages
{
    [[M13AsynchronousImageLoader defaultLoader] cancelLoadingImagesForTarget:self];
}

- (void)cancelLoadingImageAtURL:(NSURL *)url
{
    [[M13AsynchronousImageLoader defaultLoader] cancelLoadingImageAtURL:url target:self];
}

@end
