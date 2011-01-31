/* (-*- objc -*-)
 * vxSync: NSDictionaryNoEmpty.m
 * (C) 2008-2011 Nathan Hjelm
 * v0.8.3
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

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
