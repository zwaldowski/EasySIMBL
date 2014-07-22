/**
 * Copyright 2014, Zachary Waldowski
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */

#import "ESDirectoryWatcher.h"

@interface ESDirectoryWatcher ()

@property (nonatomic, readonly) dispatch_queue_t watcherQueue;
@property (nonatomic) dispatch_source_t directoryWatcherSource;

@property (nonatomic, readonly) NSFileManager *fileManager;
@property (nonatomic, readonly) NSArray *fileURLs;
@property (nonatomic, copy) NSSet *lastFileURLs;

@property (nonatomic, readonly) NSMutableDictionary *fileRemovalWatchCancelBlocksByURL;
@property (nonatomic, readonly) NSMutableDictionary *fileCopySourcesByURL;

- (void)monitorCopyingFile:(NSURL *)fileURL isReplacement:(BOOL)isReplacement;
- (void)delayHandleFile:(NSURL *)fileURL;

@end

@implementation ESDirectoryWatcher

- (instancetype)initWithDirectoryURL:(NSURL *)dirURL
{
	self = [super init];
	if (!self) return nil;
	
	_directoryURL = dirURL;
	
	_fileManager = NSFileManager.new;
	_lastFileURLs = [NSSet setWithArray:self.fileURLs];
	
	_watcherQueue = dispatch_queue_create("Directory Watcher", 0);
	
	_fileRemovalWatchCancelBlocksByURL = [NSMutableDictionary dictionary];
	_fileCopySourcesByURL = [NSMutableDictionary dictionary];
	
	return self;
}

- (void)dealloc
{
	[self stop];
}

- (void)start
{
	dispatch_async(self.watcherQueue, ^{
		dispatch_source_t source = self.directoryWatcherSource;
		if (source) {
			dispatch_source_cancel(source);
			self.directoryWatcherSource = nil;
		}
		
		int fd = open(self.directoryURL.fileSystemRepresentation, O_EVTONLY);
		if (fd < 0) { return; }
		
		if (!(self.directoryWatcherSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, DISPATCH_VNODE_WRITE, self.watcherQueue))) {
			close(fd);
			return;
		}
		
		__weak typeof(self) weakSelf = self;
		
		dispatch_source_set_event_handler(self.directoryWatcherSource, ^{
			typeof(self) s = weakSelf;
			[s handleDirectoryContentsChange];
		});
		
		dispatch_source_set_cancel_handler(self.directoryWatcherSource, ^{
			typeof(self) s = weakSelf;
			
			[s.fileRemovalWatchCancelBlocksByURL enumerateKeysAndObjectsUsingBlock:^(id _, void(^wrapper)(BOOL), BOOL *stop) {
				wrapper(YES);
			}];
			[s.fileRemovalWatchCancelBlocksByURL removeAllObjects];
			
			[s.fileCopySourcesByURL enumerateKeysAndObjectsUsingBlock:^(id _, dispatch_source_t source, BOOL *stop) {
				dispatch_source_cancel(source);
			}];
			[s.fileCopySourcesByURL removeAllObjects];
			
			close(fd);
		});
		
		dispatch_resume(self.directoryWatcherSource);
	});
}

- (void)stop
{
	dispatch_async(self.watcherQueue, ^{
		dispatch_source_t source = self.directoryWatcherSource;
		if (source) {
			dispatch_source_cancel(source);
			self.directoryWatcherSource = nil;
		}
	});
}

#pragma mark - private

- (NSArray *)fileURLs
{
	return [self.fileManager contentsOfDirectoryAtURL:self.directoryURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
}

- (void)handleDirectoryContentsChange
{
	NSArray *fileURLs = self.fileURLs;
	NSMutableSet *curFiles = [NSMutableSet setWithArray:fileURLs];
	NSMutableSet *addedFiles = [NSMutableSet setWithArray:fileURLs];
	[addedFiles minusSet:self.lastFileURLs];
	
	for (NSURL *URL in addedFiles){
		void(^wrapper)(BOOL) = self.fileRemovalWatchCancelBlocksByURL[URL];
		[self monitorCopyingFile:URL isReplacement:!!wrapper];
		if (wrapper) {
			wrapper(YES);
			[self.fileRemovalWatchCancelBlocksByURL removeObjectForKey:URL];
		}
	}
	
	NSMutableSet *removedFiles = [self.lastFileURLs mutableCopy];
	self.lastFileURLs = curFiles;
	[removedFiles minusSet:curFiles];

	for (NSURL *URL in removedFiles) { // When to replace a file, the system performs a deletion before copying, so we need to delay to check this is a file deletion or replacement
		[self delayHandleFile:URL];
	}
	
	if (!addedFiles.count && !removedFiles.count) {
		NSSet *toRemove = [self.fileRemovalWatchCancelBlocksByURL keysOfEntriesPassingTest:^(NSURL *URL, void(^wrapper)(BOOL), BOOL *stop) {
			if (![URL checkResourceIsReachableAndReturnError:NULL]) return NO;
			
			wrapper(YES);
			[self monitorCopyingFile:URL isReplacement:YES];
			return YES;
		}];
		
		[self.fileRemovalWatchCancelBlocksByURL removeObjectsForKeys:toRemove.allObjects];
	}
}

#define MAX_TRIES 10

- (void)monitorCopyingFile:(NSURL *)fileURL isReplacement:(BOOL)isReplacement
{
	if (self.fileCopySourcesByURL[fileURL]) { return; }
	
	__block int fd = open(fileURL.fileSystemRepresentation, O_EVTONLY);
	if (fd < 0) return;

	dispatch_source_t dsrc = nil;
	if (!(dsrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, DISPATCH_VNODE_ATTRIB, self.watcherQueue))) {
		close(fd);
		return;
	}
	
	self.fileCopySourcesByURL[fileURL] = dsrc;
	
	dispatch_queue_t retryQueue = dispatch_queue_create("Directory Watcher Timer", 0);
	dispatch_set_target_queue(retryQueue, self.watcherQueue);
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, retryQueue);
	
	static unsigned long long(^fileSize)(NSURL *) = ^(NSURL *URL){
		NSNumber *fs;
		if (![URL getResourceValue:&fs forKey:NSURLFileSizeKey error:NULL]) {
			return 0ULL;
		}
		return fs.unsignedLongLongValue;
	};
	
	__block unsigned long long lastFileSize = fileSize(fileURL);
	__block NSInteger possibleZeroSizeFileCheckCounter = 0;
	__block BOOL startedTimer = NO;
	__weak typeof (self) weakSelf = self;
	
	dispatch_source_set_event_handler(timer, ^{
		unsigned long long newFileSize = fileSize(fileURL);
		
		BOOL shouldPollAgain;
		
		if (fileSize == 0) {
			shouldPollAgain = ((possibleZeroSizeFileCheckCounter++) < MAX_TRIES);
		} else {
			shouldPollAgain = (newFileSize != lastFileSize);
		}
		
		if (!shouldPollAgain) {
			dispatch_source_cancel(timer);
			typeof (self) strongSelf = weakSelf;
			[strongSelf finishCopyingFile:fileURL isReplacement:isReplacement];
		}
		
		lastFileSize = newFileSize;
	});
	
	void (^startTimer)(void) = ^{
		if (startedTimer) {
			dispatch_suspend(timer);
			startedTimer = NO;
		}
		
		int64_t intervalNsec = 0.5 * NSEC_PER_SEC;
		dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, intervalNsec), intervalNsec, intervalNsec);
		
		dispatch_resume(timer);
		startedTimer = YES;
	};
	
	dispatch_source_set_event_handler(dsrc, ^{
		startTimer();
		
		typeof (self) strongSelf = weakSelf;
		strongSelf.lastFileURLs = [NSSet setWithArray:strongSelf.fileURLs];
	});
	
	dispatch_source_set_cancel_handler(dsrc, ^{
		dispatch_source_cancel(timer);
		close(fd);
	});
	
	startTimer();
	dispatch_resume(dsrc);
}

- (void)finishCopyingFile:(NSURL *)fileURL isReplacement:(BOOL)isReplacement
{
	dispatch_source_t source = self.fileCopySourcesByURL[fileURL];
	[self.fileCopySourcesByURL removeObjectForKey:fileURL];
	dispatch_source_cancel(source);
	
	BOOL confirmAndResponds = [self.delegate respondsToSelector:@selector(directoryWatcher:didFinishAddingItemAtURL:replacement:)];
	if (confirmAndResponds) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.delegate directoryWatcher:self didFinishAddingItemAtURL:fileURL replacement:isReplacement];
		});
	}
}

- (void)delayHandleFile:(NSURL *)fileURL
{
	__block BOOL cancelled = NO;
	
	dispatch_block_t block = ^{
		[self confirmDeleteFile:fileURL];
	};
	
	void (^wrapper)(BOOL) = ^(BOOL cancel) {
		if (cancel) {
			cancelled = YES;
			return;
		}
		if (!cancelled) block();
	};
	
	self.fileRemovalWatchCancelBlocksByURL[fileURL] = [wrapper copy];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), _watcherQueue, ^{
		wrapper(NO);
	});
}

- (void)confirmDeleteFile:(NSURL *)fileURL
{
	void(^wrapper)(BOOL) = self.fileRemovalWatchCancelBlocksByURL[fileURL];
	if (wrapper) {
		[self.fileRemovalWatchCancelBlocksByURL removeObjectForKey:fileURL];
		wrapper(YES);
	}

	BOOL confirmAndResponds = [self.delegate respondsToSelector:@selector(directoryWatcher:didRemoveItemAtURL:)];
	if (confirmAndResponds) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.delegate directoryWatcher:self didRemoveItemAtURL:fileURL];
		});
	}
}

@end
