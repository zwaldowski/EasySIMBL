/**
 * Copyright 2012, hetima
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */

#import <objc/message.h>
#import "SIMBL.h"
#import "SIMBLPlugin.h"
#import "ESPluginListManager.h"
#import "ESPluginListCellView.h"
#import "NSURL+ESUtilities.h"
#import "ESDirectoryWatcher.h"

@interface ESPluginListManager () <NSMenuDelegate, ESDirectoryWatcherDelegate> {
	FSEventStreamRef _eventStream;
}

@property (nonatomic, copy, readwrite) NSArray *plugins;

@property (nonatomic) NSURL *pluginsDirectoryURL;
@property (nonatomic) NSURL *disabledPluginsDirectoryURL;
@property (nonatomic) NSFileManager *fileManager;

@property (nonatomic) ESDirectoryWatcher *watcher;

@end

@implementation ESPluginListManager

- (void)directoryWatcher:(ESDirectoryWatcher *)dirWatcher didFinishAddingItemAtURL:(NSURL *)fileURL replacement:(BOOL)isReplacement
{
	NSLog(@"Added! (Replacement: %@): %@", isReplacement ? @"YES" : @"NO", fileURL);
}

- (void)directoryWatcher:(ESDirectoryWatcher *)dirWatcher didRemoveItemAtURL:(NSURL *)fileURL
{
	NSLog(@"Removed! %@", fileURL);
}

- (instancetype)init
{
    self = [super init];
    if (self) {
		_plugins = [NSMutableArray array];
		
		NSURL *applicationSupportURL = SIMBL.applicationSupportURL;
		self.pluginsDirectoryURL = [applicationSupportURL URLByAppendingPathComponent:EasySIMBLPluginsPathComponent isDirectory:YES];
		self.disabledPluginsDirectoryURL = [applicationSupportURL URLByAppendingPathComponent:[EasySIMBLPluginsPathComponent stringByAppendingString:@" (Disabled)"] isDirectory:YES];
		
		self.fileManager = NSFileManager.new;
		[self.fileManager createDirectoryAtURL:self.pluginsDirectoryURL withIntermediateDirectories:YES attributes:nil error:NULL];
		[self.fileManager createDirectoryAtURL:self.disabledPluginsDirectoryURL withIntermediateDirectories:YES attributes:nil error:NULL];

		NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(setup:) name:NSApplicationWillFinishLaunchingNotification object:NSApp];
        [nc addObserver:self selector:@selector(cleanup:) name:NSApplicationWillTerminateNotification object:NSApp];
        
    }
    return self;
}

- (void)setup:(NSNotification*)note
{
    [self scanPlugins];
    if (!_eventStream) {
        [self setupEventStream];
    }
}

- (void)cleanup:(NSNotification*)note
{
    [self invalidateEventStream];
}

- (NSArray *)scanPluginsInDirectoryAtURL:(NSURL *)directoryURL enabled:(BOOL)enabled {
	NSMutableArray *array = [NSMutableArray array];
	NSDirectoryEnumerator *enumerator = [self.fileManager enumeratorAtURL:directoryURL includingPropertiesForKeys:@[ NSURLTypeIdentifierKey ] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants|NSDirectoryEnumerationSkipsPackageDescendants errorHandler:NULL];
	
	for (NSURL *URL in enumerator) {
		SIMBLPlugin *plugin = [SIMBLPlugin pluginWithURL:URL];
		if (!plugin) { continue; }
		
		plugin.enabled = enabled;
		
		[array addObject:plugin];
	}
	
	return array;
}

- (void)scanPlugins {
	NSArray *enabledPlugins = [self scanPluginsInDirectoryAtURL:self.pluginsDirectoryURL enabled:YES];
	NSArray *disabledPlugins = [self scanPluginsInDirectoryAtURL:self.disabledPluginsDirectoryURL enabled:NO];
	
	if (disabledPlugins.count) {
		NSMutableArray *plugins = [NSMutableArray arrayWithArray:enabledPlugins];
		[plugins addObjectsFromArray:disabledPlugins];
		[plugins sortUsingComparator:^NSComparisonResult(SIMBLPlugin *obj1, SIMBLPlugin *obj2) {
			NSComparisonResult result = [obj1.name compare:obj2.name];
			
			if (result == NSOrderedSame) {
				obj1.fileSystemConflict = YES;
				obj2.fileSystemConflict = YES;
			}
			
			return result;
		}];
		
		self.plugins = plugins;
	} else {
		self.plugins = enabledPlugins;
	}
}

#pragma mark - action

// from checkbox on tableview
- (IBAction)actToggleEnabled:(id)sender
{
    ESPluginListCellView *cellView=(ESPluginListCellView *)[sender superview];
	SIMBLPlugin *target = cellView.objectValue;
	
    //enabled value is already new
	BOOL bEnabled = target.enabled;
    if ([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask) {
		for (SIMBLPlugin *plugin in self.plugins) {
			[self switchEnabled:bEnabled forPlugin:plugin];
		}
    } else {
		[self switchEnabled:bEnabled forPlugin:target];
    }
    
    [self scanPlugins];
}

// from x button on tableview
// show confirm popover
- (IBAction)actConfirmUninstall:(id)sender
{
    if (self.removePopover.delegate) {
        [self.removePopover performClose:self];
        return;
    }
    
    ESPluginListCellView* cellView=(ESPluginListCellView*)[sender representedObject];
	SIMBLPlugin *target = cellView.objectValue;
	NSString *caption = [NSString localizedStringWithFormat:@"Are you sure you want to uninstall \"%@\" ?", target.name];
    
    [self.removePopoverCaption setStringValue:caption];
    
    
    //popover の delegate でアンインストールするプラグインを把握
    [self.removePopover setDelegate:cellView];
    [self.removePopover showRelativeToRect:[[self.removePopover.contentViewController view]bounds] ofView:cellView preferredEdge:CGRectMinYEdge];
}

// from Uninstall button on popover
- (IBAction)actDecideUninstall:(id)sender
{
    ESPluginListCellView* cellView=(ESPluginListCellView*)self.removePopover.delegate;
    SIMBLPlugin *target = cellView.objectValue;
    [self.removePopover performClose:self];
	[self uninstallPlugin:target];
}

- (IBAction)actShowPluginFolder:(id)sender
{
	[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ self.pluginsDirectoryURL ]];
}

- (NSMenu *)menuForTableView:(NSTableView *)tableView row:(NSInteger)row
{
	if (self.plugins.count <= row) {
		return nil;
	}
	
	SIMBLPlugin *plugin = self.plugins[row];
	
    NSMenu *menu=[[NSMenu alloc]initWithTitle:@"menu"];
    NSView *cellView=[tableView viewAtColumn:0 row:row makeIfNecessary:NO];
    NSMenuItem *item = [menu addItemWithTitle:[NSString localizedStringWithFormat:@"Uninstall \"%@\" ...", plugin.name] action:@selector(actConfirmUninstall:) keyEquivalent:@""];
    [item setRepresentedObject:cellView];
    [item setTarget:self];
	
    [menu addItem:NSMenuItem.separatorItem];
	
    [menu addItemWithTitle:@"SIMBLTargetApplications:" action:nil keyEquivalent:@""];
	NSDictionary *bundleInfo = plugin.bundleInfo;
    NSArray* targetApps = [bundleInfo objectForKey:SIMBLTargetApplications];
    for (NSDictionary* targetApp in targetApps) {
        NSNumber* number;
        NSString* appID = [targetApp objectForKey:SIMBLBundleIdentifier];
        NSInteger minVer = 0;
        NSInteger maxVer = 0;
        number=[targetApp objectForKey:SIMBLMinBundleVersion];
        if (number) {
            minVer=[number integerValue];
        }
        number = [targetApp objectForKey:SIMBLMaxBundleVersion];
        if (number) {
            maxVer=[number integerValue];
        }
        
        item = [menu addItemWithTitle:appID action:nil keyEquivalent:@""];
        [item setIndentationLevel:1];
        if (minVer || maxVer) {
            NSString* minVerStr = minVer ? [NSString stringWithFormat:@"%li", minVer] : @"";
            NSString* maxVerStr = maxVer ? [NSString stringWithFormat:@"%li", maxVer] : @"";
            NSString* verStr=[NSString stringWithFormat:@"version:%@ - %@", minVerStr, maxVerStr];
            item = [menu addItemWithTitle:verStr action:nil keyEquivalent:@""];
            [item setIndentationLevel:2];
        }
    }
    return menu;
}


#pragma mark - file manage

- (void)switchEnabled:(BOOL)enabled forPlugin:(SIMBLPlugin *)plugin
{
	NSURL *destination = [self installationURLForBundleAtURL:plugin.URL enabled:enabled];
	[self.fileManager moveItemAtURL:plugin.URL toURL:destination error:NULL];
}

// install. copy to plugin dir
- (void)installPluginsFromURLs:(NSArray *)plugins
{
	NSMutableSet *URLsToTrash = [NSMutableSet set];
	NSMutableDictionary *URLsToInstall = [NSMutableDictionary dictionary];
	
	for (NSURL *URL in plugins) {
		//check from plugin folder
		if ([URL es_isChildOfURL:self.pluginsDirectoryURL]) {
			continue;
		}
		
		//check already installed
		NSURL *installURL = nil;
		NSURL *installedURL = [self installedURLForBundleAtURL:URL installationURL:&installURL];
		
		if (!installedURL) {
			[self installPluginAtURL:URL toURL:installURL];
			continue;
		}
		
		// already installed
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = [NSString localizedStringWithFormat:@"\"%@\" is already exists. Do you want to replace it?", URL.lastPathComponent.stringByDeletingPathExtension];
		alert.informativeText = NSLocalizedString(@"If replaced, the existing plugin is moved to the Trash.", nil);
		[alert addButtonWithTitle:NSLocalizedString(@"Replace", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
		
		[alert beginSheetModalForWindow:self.listView.window completionHandler:^(NSModalResponse returnCode) {
			if (returnCode != NSAlertFirstButtonReturn) { return; }
			
			[URLsToTrash addObject:installedURL];
			URLsToInstall[URL] = installURL;
		}];
	}
	
	[NSWorkspace.sharedWorkspace recycleURLs:URLsToTrash.allObjects completionHandler:^(NSDictionary *newURLs, NSError *error) {
		[URLsToInstall enumerateKeysAndObjectsUsingBlock:^(NSURL *URL, NSURL *installURL, BOOL *stop) {
			[self installPluginAtURL:URL toURL:installURL];
		}];
		
		[self scanPlugins];
	}];
}

- (void)installPluginAtURL:(NSURL *)URL toURL:(NSURL *)installURL
{
	NSError *err;
	if (![self.fileManager copyItemAtURL:URL toURL:installURL error:&err]){
		SIMBLLogNotice(@"install error:%@", err);
	}
}

- (NSURL *)installationURLForBundleAtURL:(NSURL *)URL enabled:(BOOL)enabled
{
	NSURL *destination = enabled ? self.pluginsDirectoryURL : self.disabledPluginsDirectoryURL;
	return [destination URLByAppendingPathComponent:URL.lastPathComponent isDirectory:YES];
}

- (NSURL *)installedURLForBundleAtURL:(NSURL *)URL installationURL:(out NSURL **)outInstallationURL
{
	NSURL *pluginURL = [self installationURLForBundleAtURL:URL enabled:YES];
	if ([pluginURL checkResourceIsReachableAndReturnError:NULL]) {
		if (outInstallationURL) *outInstallationURL = nil;
		return pluginURL;
	}
	
	if (outInstallationURL) *outInstallationURL = pluginURL;

	pluginURL = [self installationURLForBundleAtURL:URL enabled:NO];
	if ([pluginURL checkResourceIsReachableAndReturnError:NULL]) {
		return pluginURL;
	}
	
	return nil;
}

// uninstall. move to trash
- (void)uninstallPlugin:(SIMBLPlugin *)plugin
{
	if (!plugin) { return; }
	[NSWorkspace.sharedWorkspace recycleURLs:@[ plugin.URL ] completionHandler:^(NSDictionary *newURLs, NSError *error){
		[self scanPlugins];
	}];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	[menu removeAllItems];
	
	NSInteger row = self.listView.clickedRow;
	if (row < 0 || row >= self.plugins.count) { return; }

	SIMBLPlugin *plugin = self.plugins[row];
	
	NSView *cellView=[self.listView viewAtColumn:0 row:row makeIfNecessary:NO];
	NSMenuItem *item = [menu addItemWithTitle:[NSString localizedStringWithFormat:@"Uninstall \"%@\"…", plugin.name] action:@selector(actConfirmUninstall:) keyEquivalent:@""];
	[item setRepresentedObject:cellView];
	[item setTarget:self];
	
	[menu addItem:NSMenuItem.separatorItem];
	
	[menu addItemWithTitle:NSLocalizedString(@"SIMBL Target Applications", nil) action:nil keyEquivalent:@""];
	NSDictionary *bundleInfo = plugin.bundleInfo;
	NSArray* targetApps = [bundleInfo objectForKey:SIMBLTargetApplications];
	for (NSDictionary* targetApp in targetApps) {
		NSNumber* number;
		NSString* appID = [targetApp objectForKey:SIMBLBundleIdentifier];
		NSInteger minVer = 0;
		NSInteger maxVer = 0;
		number=[targetApp objectForKey:SIMBLMinBundleVersion];
		if (number) {
			minVer=[number integerValue];
		}
		number = [targetApp objectForKey:SIMBLMaxBundleVersion];
		if (number) {
			maxVer=[number integerValue];
		}
		
		item = [menu addItemWithTitle:appID action:nil keyEquivalent:@""];
		[item setIndentationLevel:1];
		if (minVer || maxVer) {
			NSString* minVerStr = minVer ? [NSString stringWithFormat:@"%li", minVer] : @"";
			NSString* maxVerStr = maxVer ? [NSString stringWithFormat:@"%li", maxVer] : @"";
			NSString* verStr=[NSString stringWithFormat:@"version:%@ - %@", minVerStr, maxVerStr];
			item = [menu addItemWithTitle:verStr action:nil keyEquivalent:@""];
			[item setIndentationLevel:2];
		}
	}

}

#pragma mark FSEvents

#define ESFSEventStreamLatency			((CFTimeInterval)3.0)

static void ESFSEventsCallback(
                               ConstFSEventStreamRef streamRef,
                               void *callbackCtxInfo,
                               size_t numEvents,
                               void *eventPaths,
                               const FSEventStreamEventFlags eventFlags[],
                               const FSEventStreamEventId eventIds[])
{
	ESPluginListManager *watcher = (__bridge ESPluginListManager *)callbackCtxInfo;
    [watcher scanPlugins];
}

- (void)invalidateEventStream{
    if (_eventStream) {
        FSEventStreamStop(_eventStream);
        FSEventStreamInvalidate(_eventStream);
        FSEventStreamRelease(_eventStream);
        _eventStream = nil;
    }
	
	if (self.watcher) {
		[self.watcher stop];
		self.watcher = nil;
	}
}

- (void)setupEventStream
{
    [self invalidateEventStream];
	
	NSURL *testURL = SIMBL.applicationSupportURL;
	testURL = [testURL URLByAppendingPathComponent:@"Test" isDirectory:YES];
	
	self.watcher = [[ESDirectoryWatcher alloc] initWithDirectoryURL:testURL];
	self.watcher.delegate = self;
	[self.watcher start];
	
    NSArray* watchPaths= @[ self.pluginsDirectoryURL.path, self.disabledPluginsDirectoryURL.path ];
    
    FSEventStreamCreateFlags   flags = (kFSEventStreamCreateFlagIgnoreSelf);
    
	FSEventStreamContext callbackCtx;
	callbackCtx.version = 0;
	callbackCtx.info = (__bridge void *)self;
	callbackCtx.retain = NULL;
	callbackCtx.release = NULL;
	callbackCtx.copyDescription	= NULL;
    
	_eventStream = FSEventStreamCreate(kCFAllocatorDefault,
									   &ESFSEventsCallback,
									   &callbackCtx,
									   (__bridge CFArrayRef)watchPaths,
									   kFSEventStreamEventIdSinceNow,
									   ESFSEventStreamLatency,
									   flags);
    FSEventStreamScheduleWithRunLoop(_eventStream, [[NSRunLoop currentRunLoop]getCFRunLoop], kCFRunLoopDefaultMode);
    if (!FSEventStreamStart(_eventStream)) {
        
    }
}

#pragma mark -


- (void)awakeFromNib
{
	[super awakeFromNib];
	
	[self.listView registerForDraggedTypes:@[ (__bridge id)kUTTypeFileURL ]];
}

static BOOL(^URLIsBundleTest)(id, NSUInteger, BOOL *) = ^BOOL(NSURL *URL, NSUInteger idx, BOOL *_) {
	NSString *UTI = nil;
	if (![URL getResourceValue:&UTI forKey:NSURLTypeIdentifierKey error:NULL]) {
		return NO;
	}
	
	return UTTypeConformsTo((__bridge CFStringRef)UTI, kUTTypeBundle);
};

- (void)tableView:(NSTableView *)tableView updateDraggingItemsForDrag:(id <NSDraggingInfo>)draggingInfo
{
	draggingInfo.draggingFormation = NSDraggingFormationList;
	if ([draggingInfo.draggingSource isEqual:tableView]) { return; }
	
	NSTableColumn *tableColumn = tableView.tableColumns[0];
	NSTableCellView *tableCellView = [tableView makeViewWithIdentifier:@"PluginListCellView" owner:self];
	
	CGSize spacing = tableView.intercellSpacing;
	
	__block NSRect cellFrame = CGRectMake(0, 0, tableColumn.width - spacing.width, tableView.rowHeight);
	__block NSInteger validCount = 0;
	[draggingInfo enumerateDraggingItemsWithOptions:0 forView:tableView classes:@[ NSPasteboardItem.class ] searchOptions:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES } usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
		NSPasteboardItem *item = draggingItem.item;
		NSString *URLtype = [item availableTypeFromArray:@[ (__bridge id)kUTTypeFileURL ]];
		NSURL *URL = URLtype ? [NSURL URLWithString:[item stringForType:URLtype]] : nil;
		SIMBLPlugin *plugin = [SIMBLPlugin pluginWithURL:URL];
		
		if (!plugin) {
			draggingItem.imageComponentsProvider = NULL;
			return;
		}
		
		draggingItem.draggingFrame = cellFrame;
		draggingItem.imageComponentsProvider = ^{
			tableCellView.objectValue = plugin;
			tableCellView.frame = cellFrame;
			return tableCellView.draggingImageComponents;
		};
		
		cellFrame.origin.y += NSHeight(cellFrame) + spacing.height;
		validCount++;
	}];
	
	draggingInfo.numberOfValidItemsForDrop = validCount;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
	if ([info draggingSource] == tableView)
		return NSDragOperationNone;
	
	[tableView setDropRow:-1 dropOperation:NSTableViewDropOn];
	return NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation
{
	NSArray *URLs = [info.draggingPasteboard readObjectsForClasses:@[ NSURL.class ] options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
	NSIndexSet *items = [URLs indexesOfObjectsWithOptions:NSEnumerationConcurrent passingTest:URLIsBundleTest];
	NSArray *bundleURLs = [URLs objectsAtIndexes:items];
	
	if (!bundleURLs.count) return NO;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self installPluginsFromURLs:bundleURLs];
	});
	return YES;
}

@end
