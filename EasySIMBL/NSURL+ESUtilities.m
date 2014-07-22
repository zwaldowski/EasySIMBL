/**
 * Copyright 2014, Zachary Waldowski
 * EasySIMBL is released under the GNU General Public License v2.
 * http://www.opensource.org/licenses/gpl-2.0.php
 */

#import "NSURL+ESUtilities.h"

@implementation NSURL (ESUtilities)

- (BOOL)es_isChildOfURL:(NSURL *)baseURL
{
	if (baseURL == nil) { return NO; }
	
	NSString *basePath = baseURL.URLByStandardizingPath.path;
	NSString *originalPath = self.URLByStandardizingPath.path;
	
	if ([originalPath isEqualToString:basePath]) { return YES; }
	
	if (![basePath hasSuffix: @"/"])
		basePath = [basePath stringByAppendingString:@"/"];
	
	if (![originalPath hasSuffix: @"/"])
		originalPath = [originalPath stringByAppendingString:@"/"];
	
	return [originalPath hasPrefix:basePath];
}

- (BOOL)es_isEqualToFileURL:(NSURL *)other {
	if (![other isKindOfClass:NSURL.class]) return NO;
	
	BOOL isFile = self.isFileURL, otherFile = other.isFileURL;
	BOOL isEqual = [self isEqual:other];
	
	if (isEqual || (!isFile && !otherFile)) {
		return isEqual;
	}
	
	NSError *error = nil;
	id resourceIdentifier1 = nil;
	id resourceIdentifier2 = nil;
	
	if (![self getResourceValue:&resourceIdentifier1 forKey:NSURLFileResourceIdentifierKey error:&error]) {
		return NO;
	}
	
	if (![other getResourceValue:&resourceIdentifier2 forKey:NSURLFileResourceIdentifierKey error:&error]) {
		return NO;
	}
	
	return [resourceIdentifier1 isEqual:resourceIdentifier2];
}

@end
