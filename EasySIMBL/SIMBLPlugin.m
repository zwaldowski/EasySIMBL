//
//  SIMBLPlugin.m
//  EasySIMBL
//
//  Created by Zachary Waldowski on 7/12/14.
//
//

#import "SIMBLPlugin.h"
#import "SIMBL.h"
#import "NSURL+ESUtilities.h"

@interface SIMBLPlugin ()

@property (nonatomic, readonly) NSBundle *bundle;

@end

@implementation SIMBLPlugin

- (instancetype)initWithBundle:(NSBundle *)bundle
{
	self = [super init];
	if (!self) return self;
	
	_bundle = bundle;
	
	return self;
}

- (instancetype)initWithURL:(NSURL *)URL
{
	self = [super init];
	if (!self) return self;
	
	return (self = [self initWithBundle:[NSBundle bundleWithURL:URL]]);
}

+ (instancetype)pluginWithURL:(NSURL *)URL
{
	NSString *UTI = nil;
	if (![URL getResourceValue:&UTI forKey:NSURLTypeIdentifierKey error:NULL] || !UTTypeConformsTo((__bridge CFStringRef)UTI, kUTTypeBundle)) {
		return nil;
	}
	
	return [[self alloc] initWithBundle:[NSBundle bundleWithURL:URL]];
}

- (instancetype)copyWithZone:(NSZone *)zone
{
	return [[[self class] allocWithZone:zone] initWithBundle:_bundle];
}

- (NSURL *)URL
{
	return self.bundle.bundleURL;
}

- (NSString *)path
{
	return self.bundle.bundlePath;
}

- (NSString *)name
{
	return self.URL.lastPathComponent.stringByDeletingPathExtension;
}

- (NSString *)bundleIdentifier
{
	return _bundle.bundleIdentifier.description;
}

- (NSDictionary *)bundleInfo
{
	return _bundle.SIMBL_infoDictionary;
}

- (NSString *)bundleVersion
{
	NSString *bundleVersion = self.bundle._dt_version;
	if (bundleVersion.length) return bundleVersion;
	return self.bundle._dt_bundleVersion;
}

- (NSString *)description
{
	NSString *bundleVersion = self.bundleVersion;
	NSString *bundleIdentifier = self.bundleIdentifier;
	if (!bundleVersion.length) return bundleIdentifier;
	return [NSString stringWithFormat:@"%@ - %@", bundleVersion, bundleIdentifier];
}

- (BOOL)isEqual:(SIMBLPlugin *)other
{
	if (![other isKindOfClass:SIMBLPlugin.class]) return NO;
	return [self.URL es_isEqualToFileURL:other.URL];
}

- (NSUInteger)hash
{
	return self.URL.hash;
}

@end
