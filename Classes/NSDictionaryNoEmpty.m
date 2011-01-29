//
//  NSDictionaryNoEmpty.m
//  vxSync
//
//  Created by Nathan Hjelm on 1/20/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "NSDictionaryNoEmpty.h"

@interface vxKeyValue : NSObject
{
@private
  NSString *key;
  NSMutableDictionary *value;
  BOOL isExplicitlyIncluded;
}

@property (retain) NSString *key;
@property (retain) NSMutableDictionary *value;
@property (readwrite) BOOL isExplicitlyIncluded;

@end

@implementation vxKeyValue

@synthesize key, value, isExplicitlyIncluded;

- (void) _setWithoutNotificationLocalizedKey: (id) foo key: (id) _key {
  [key release];
  key = [_key retain];
  fprintf (stderr, "foo = %s, key = %s\n", [[foo description] UTF8String], [[key description] UTF8String]);
}

- (void) _setValueWithoutNotification: (id) _value {
  [value release];
  value = [_value retain];
}

- (void) _markAsExplicitlyIncluded: (BOOL) mark {
  [self setIsExplicitlyIncluded: mark];
}
@end


@implementation NSDictionaryNoEmpty

- (BOOL)setSelectionIndexes:(NSIndexSet *)indexes {
  if (![indexes count])
    return NO;
  
  return [super setSelectionIndexes: indexes];
}

- (id) newObject {
  return [[vxKeyValue alloc] init];
}

@end
