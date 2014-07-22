/**
 * Copyright 2012, hetima
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */

#import <Foundation/Foundation.h>

// this class is tableview delegate so that receive action from inside of table cell view etc.

@interface ESPluginListManager : NSObject <NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate>

@property (nonatomic, copy, readonly) NSArray *plugins;

@property (nonatomic, weak) IBOutlet NSPopover *removePopover;
@property (nonatomic, weak) IBOutlet NSTextField *removePopoverCaption;
@property (nonatomic, weak) IBOutlet NSTableView *listView;

- (void)installPluginsFromURLs:(NSArray *)plugins;

@end
