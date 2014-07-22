//
//  SIMBLPlugin.h
//  EasySIMBL
//
//  Created by Zachary Waldowski on 7/12/14.
//
//

#import <Foundation/Foundation.h>

@interface SIMBLPlugin : NSObject <NSCopying>

+ (instancetype)pluginWithURL:(NSURL *)URL;

- (instancetype)initWithURL:(NSURL *)URL DEPRECATED_ATTRIBUTE;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSString *path DEPRECATED_ATTRIBUTE;

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *bundleVersion;
@property (nonatomic, copy, readonly) NSDictionary *bundleInfo;

@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, getter=hasFileSystemConflict) BOOL fileSystemConflict;

@end
