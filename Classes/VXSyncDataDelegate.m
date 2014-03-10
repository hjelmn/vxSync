/* (-*- objc -*-)
 * vxSync: VXSyncDataDelegate.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
 *
 * Changes:
 *  - 0.3.1 - Move LGException class into a seperate file. Bug fixes and code cleanup
 *  - 0.3.0 - Cleaner code. Support for commitChanges. Better support for all day events. Multiple calendars support.
 *  - 0.2.3 - Bug fixes
 *  - 0.2.0 - Initial release
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

#include "VXSyncDataDelegate.h"

@implementation VXSyncDataSource (DataDelegate)

#pragma mark LGDataDelegate methods

- (void) getIdentifierForRecord: (NSMutableDictionary *) objectIn compareKeys: (NSArray *) keys {
  NSDictionary *records = [persistentStore objectForKey: [objectIn objectForKey: RecordEntityName]];
  NSString *identifier = nil;
  NSDictionary *dataSourceDict = [dataSources objectForKey: [supportedEntities objectForKey: [objectIn objectForKey: RecordEntityName]]];
  int mode = [[dataSourceDict valueForKeyPath: @"mode"] intValue];

  if (VXSYNC_MODE_PHONE_OW != mode)
    if ([keys count])
      for (identifier in records) {
        id record = [records objectForKey: identifier];
        BOOL isFound = YES;
        
        for (id key in keys) {
          if (![[objectIn objectForKey: key] isEqual: [record objectForKey: key]] && [objectIn objectForKey: key] != [record objectForKey: key]) {
            isFound = NO;
            break;
          }
        }
        
        if (YES == isFound)
          break;
      }
  
  if (!identifier) {
    /* create a new uuid for the object */
    CFUUIDRef uuid = CFUUIDCreate (NULL); 
    identifier = (NSString *)CFUUIDCreateString (NULL, uuid);
    CFRelease(uuid);
  }

  [objectIn setObject: identifier forKey: VXKeyIdentifier];
}

- (id) removeRecordWithIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName {
  id record = [self findRecordWithIdentifier: identifier entityName: entityName];

  [[persistentStore objectForKey: entityName] removeObjectForKey: identifier];

  return record;
}

- (id) findRecordWithIdentifier: (NSString *) identifier entityName: (NSString *) entityName {
  if (!identifier || !entityName)
    return nil;

  return [[persistentStore objectForKey: entityName] objectForKey: identifier];
}

- (void) addRecord: (NSDictionary *) record withIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName {
  NSMutableDictionary *recordDict = [NSMutableDictionary dictionaryWithDictionary: record];
  NSMutableDictionary *entities = [persistentStore objectForKey: entityName];
  
  if (nil == entities) {
    entities = [NSMutableDictionary dictionary];
    [persistentStore setObject: entities forKey: entityName];
  }

  [recordDict setObject: identifier forKey: VXKeyIdentifier];
  [entities setObject: recordDict forKey: identifier];
}

- (void) modifyRecord: (NSDictionary *) record withIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName {
  (void) [self removeRecordWithIdentifier: identifier withEntityName: entityName];
  [self addRecord: record withIdentifier: identifier withEntityName: entityName];
}
/* end delegate methods */

@end
