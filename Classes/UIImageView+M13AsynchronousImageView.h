//
//  UIImageView+M13AsynchronousImageView.h
//  M13AsynchronousImageView
//
//  Created by Brandon McQuilkin on 4/24/14.
//  Copyright (c) 2014 Brandon McQuilkin. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef enum {
    M13AsynchronousImageLoaderImageLoadedLocationNone,
    M13AsynchronousImageLoaderImageLoadedLocationCache,
    M13AsynchronousImageLoaderImageLoadedLocationLocalFile,
    M13AsynchronousImageLoaderImageLoadedLocationExternalFile
} M13AsynchronousImageLoaderImageLoadedLocation;

/**
 The completion block for loading an image.
 
 @param success Wether or not the load succeded.
 @param url     The URL of the image.
 @param target  The designated target for loading the image if a target exists. (Usually a UIImageView.)
 */
typedef void (^M13AsynchronousImageLoaderCompletionBlock)(BOOL success, M13AsynchronousImageLoaderImageLoadedLocation location, UIImage *__nullable image, NSURL *__nullable url, id __nullable target);

@interface M13AsynchronousImageLoader : NSObject

/**@name Control Methods*/
/**
 Returns the default asynchronous image loader. The default loader is named "Default". This is the method most people will use to get the image loader.
 
 @return The default asynchronous image loader.
 */
+ (M13AsynchronousImageLoader *__nonnull)defaultLoader;
/**
 Returns an asynchronous image loader with the given name. If no loader exists with that name, one will be created.
 
 @param name The name of the asynchronous image loader to retreive.
 
 @return The asynchronous image loader with the given name.
 */
+ (M13AsynchronousImageLoader *__nonnull)loaderWithName:(NSString *__nonnull)name;
/**
 Clears, and removes from memory the asynchronous image loader with the given name.
 
 @param name The name of the asynchronous image loader to cleanup.
 */
+ (void)cleanupLoaderWithName:(NSString *__nonnull)name;
/**
 The cache all asynchronous image loaders will use, unless set otherwise.
 
 @return The default image Cache.
 */
+ (NSCache *__nonnull)defaultImageCache;

/**@name Loading Images*/
/**
 Loads the image at the given URL into the cache.
 
 @note The url can be internal or external.
 
 @param url The URL of the image to download.
 */
- (void)loadImageAtURL:(NSURL *__nullable)url;
/**
 Loads the image at the given URL. When the image has loaded then perform the given completion block.
 
 @note The URL can be internal or external.
 
 @param url    The URL to load the image from.
 @param target The target of the image loading.
 @param completion The completion block to run when finished loading the image.
 */
- (void)loadImageAtURL:(NSURL *__nullable)url target:(id __nullable)target completion:(M13AsynchronousImageLoaderCompletionBlock __nullable)completion;
/**
 Loads the image at the given URL and stores it at fileURL. When the image has loaded then perform the given completion block.
 
 @note The URL can be internal or external.
 
 @param url    The URL to load the image from.
 @param fileURL    The URL to store the image to.
 @param target The target of the image loading.
 @param completion The completion block to run when finished loading the image.
 */
- (void)loadImageAtURL:(NSURL *__nullable)url fileURL:(NSURL *__nullable)fileURL target:(id __nullable)target completion:(M13AsynchronousImageLoaderCompletionBlock __nullable)completion;
/**
 Cancels loading the image at the given URL.
 
 @param url The URL of the image to cancel downloading of.
 */
- (void)cancelLoadingImageAtURL:(NSURL *__nonnull)url;
/**
 Cancel loading the images set to be loaded for the given target.
 
 @param target The target to cancel loading the images for.
 */
- (void)cancelLoadingImagesForTarget:(id __nonnull)target;
/**
 Cancels loading the image at the given URL, for the given target.
 
 @param url        The URL of the image to cancel.
 @param target     The target to cancel the loading of the image for.
 */
- (void)cancelLoadingImageAtURL:(NSURL * __nonnull)url target:(id __nonnull)target;


/**@name Properties*/
/**
 The cache the image loader will use to cache the images.
 */
@property (nonatomic, strong, nonnull) NSCache *imageCache;
/**
 The maximum number of images to load concurrently.
 */
@property (nonatomic, assign) NSUInteger maximumNumberOfConcurrentLoads;
/**
 The length of time to try and load an image before stopping.
 */
@property (nonatomic, assign) NSTimeInterval loadingTimeout;


@end

@interface UIImageView (M13AsynchronousImageView)
/**
 *  The maximum number of objects the image cache should hold.
 *  Default value is 0 - unlimited
 *
 *  @param cacheLimit New value for maximum cache capacity of images
 */
+ (void)setCacheLimit:(NSUInteger) cacheLimit;

/**
 Load the image from the given URL, then set the loaded image to the image property.
 
 @param url The URL to download the image from.
 */
- (void)loadImageFromURL:(NSURL * __nonnull)url;
/**
 Load the image from the given URL to fileURL, then set the loaded image to the image property.
 
 @param url The URL to download the image from.
 @param fileURL    The URL to save the image to.
 */
- (void)loadImageFromURL:(NSURL * __nonnull)url toFileURL:(NSURL * __nullable)fileURL;
/**
 Loads the image from the given URL. Then set the loaded image to the image property. After the image is finished loading, the completion block will be run.
 
 @note If using this method in a table or collection view, one will likely have to refresh the cell containing the image view once the image has been set; If the location value in the completion block is not from the cache. If it is from the cache, the image was set immediatly, and no additional action should be required.
 
 @param url        The URL to load the image from.
 @param completion The completion block to run once the image has been downloaded.
 */
- (void)loadImageFromURL:(NSURL * __nonnull)url completion:(M13AsynchronousImageLoaderCompletionBlock __nullable)completion;

/**
 Loads the image from the given URL to fileURL. Then set the loaded image to the image property. After the image is finished loading, the completion block will be run.
 
 @note If using this method in a table or collection view, one will likely have to refresh the cell containing the image view once the image has been set; If the location value in the completion block is not from the cache. If it is from the cache, the image was set immediatly, and no additional action should be required.
 
 @param url        The URL to load the image from.
 @param fileURL    The URL to save the image to.
 @param completion The completion block to run once the image has been downloaded.
 */
- (void)loadImageFromURL:(NSURL * __nonnull)url toFileURL:(NSURL * __nullable)fileURL completion:(M13AsynchronousImageLoaderCompletionBlock __nullable)completion;

/**
 Cancels loading all the images set to load for the image view.
 */
- (void)cancelLoadingAllImages;
/**
 Cancels loading the image at the given URL set to load for the image view.
 
 @param url The URL of the image to cancel loading of.
 */
- (void)cancelLoadingImageAtURL:(NSURL * __nonnull)url;
/**
 *  Loads the image from application cache directory. Then set the loaded image to the image property. After the image is finished loading, the completion block will be run.
 *
 *  @param path       path after 'pathToApplication/Library/Caches/'
 *  @param completion The completion block to run once the image has been downloaded.
 */
- (void)loadImageFromCachePath:(NSString * __nonnull)path completion:(M13AsynchronousImageLoaderCompletionBlock __nullable)completion;
/**
 *  Loads the image from application Caches directory. Then set the loaded image to the image property.
 *
 *  @param path path after 'pathToApplication/Library/Caches/'
 */
- (void)loadImageFromCachePath:(NSString * __nonnull)path;

/**
 *  Loads the image from application Documents directory. Then set the loaded image to the image property. After the image is finished loading, the completion block will be run.
 *
 *  @param path       path after 'pathToApplication/Documents/'
 *  @param completion The completion block to run once the image has been downloaded.
 */
- (void)loadImageFromDocumentPath:(NSString * __nonnull)path completion:(M13AsynchronousImageLoaderCompletionBlock __nullable)completion;
/**
 *  Loads the image from application Documents directory. Then set the loaded image to the image property.
 *
 *  @param path path after 'pathToApplication/Documents/'
 */
- (void)loadImageFromDocumentPath:(NSString * __nonnull)path;

@end
