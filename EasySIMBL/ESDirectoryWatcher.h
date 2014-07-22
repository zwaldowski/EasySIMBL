/**
 * Copyright 2014, Zachary Waldowski
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */

#import <Foundation/Foundation.h>

@class ESDirectoryWatcher;

@protocol ESDirectoryWatcherDelegate <NSObject>

@optional

- (void)directoryWatcher:(ESDirectoryWatcher *)dirWatcher didFinishAddingItemAtURL:(NSURL *)fileURL replacement:(BOOL)isReplacement;
- (void)directoryWatcher:(ESDirectoryWatcher *)dirWatcher didRemoveItemAtURL:(NSURL *)fileURL;

@end

@interface ESDirectoryWatcher : NSObject

@property (nonatomic, weak) id <ESDirectoryWatcherDelegate> delegate;
@property (nonatomic, readonly) NSURL *directoryURL;

- (instancetype)initWithDirectoryURL:(NSURL *)dirURL;
- (void)start;
- (void)stop;

@end
