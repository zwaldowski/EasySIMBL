/**
 * Copyright 2012, hetima
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */


#import "ESPluginListCellView.h"

@implementation ESPluginListCellView

#pragma mark - <NSPopoverDelegate>

- (void)popoverWillShow:(NSNotification *)notification
{
    
}

- (void)popoverWillClose:(NSNotification *)notification
{
    [[notification object] setDelegate:nil];
}

@end
