/* (-*- objc -*-)
 * vxSync: NSDictionaryNoEmpty.m
 * (C) 2008-2011 Nathan Hjelm
 * v0.8.3
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU  General Public
 * License as published by the Free Software Foundation; either
 * version 3.0 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU  General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "NSDictionaryNoEmpty.h"

/*
  vxKeyValue:
   - an NSDictionaryControllerKeyValuePair that stores mutable dictionary values (the default pair only supports non-mutable values)
 */

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


/*
 NSDictionaryNoEmpty:
  - NSDictionaryController that 
 */
@implementation NSDictionaryNoEmpty

- (BOOL)setSelectionIndexes:(NSIndexSet *)indexes {
  if (![indexes count])
    return NO;
  
  return [super setSelectionIndexes: indexes];
}

#if 0
- (id) newObject {
  return [[vxKeyValue alloc] init];
}
#endif

@end
