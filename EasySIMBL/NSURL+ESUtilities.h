/**
 * Copyright 2014, Zachary Waldowski
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */

#import <Foundation/Foundation.h>

@interface NSURL (ESUtilities)

- (BOOL)es_isChildOfURL:(NSURL *)baseURL;

- (BOOL)es_isEqualToFileURL:(NSURL *)other;

@end
