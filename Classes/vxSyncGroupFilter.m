/* (-*- objc -*-)
 * vxSync: vxSyncGroupFilter.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.5.1 - Feb 13, 2010
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

#include "vxSyncGroupFilter.h"

@implementation vxSyncGroupFilter

#pragma mark properties
@synthesize groupNames, clientIdentifier, syncAllGroups, snapshot, syncOnlyWithPhoneNumbers;

#pragma mark allocation/deallocation

+ (vxSyncGroupFilter *) filter {
  return [[[vxSyncGroupFilter alloc] init] autorelease];
}

- (id) init {
  return [super init];
}

- (void) dealloc {
  [self setSnapshot: nil];
  [self setGroupNames: nil];
  [self setClientIdentifier: nil];

  [super dealloc];
}

#pragma mark ISyncFiltering

- (NSArray *) supportedEntityNames {
  return [NSArray arrayWithObjects: EntityGroup, EntityContact, EntityNumber, EntityEmail, EntityAddress, EntityIM, nil];
}

- (BOOL) shouldApplyRecord: (NSDictionary *) record withRecordIdentifier: (NSString *) recordIdentifier {
  [[vxSyncLogger defaultLogger] addMessageWithLevel: VXSYNC_LOG_DEBUG func: __func__ line: __LINE__ format: @"filtering record: %s\n", NS2CH(record)];
  
  if ([[record objectForKey: RecordEntityName] isEqualToString: EntityContact] && ![[record objectForKey: @"first name"] length] && ![[record objectForKey: @"last name"] length])
    /* record has no name */
    return NO;
  
  if (![[record objectForKey: RecordEntityName] isEqual: EntityGroup]) {
    NSDictionary *groupRecords, *contactRecord, *numberRecords;
    BOOL contactCanBeSynced = NO;

    if (!snapshot)
      [self setSnapshot: [[ISyncManager sharedManager] snapshotOfRecordsInTruthWithEntityNames: [NSArray arrayWithObjects: EntityGroup, EntityContact, nil] usingIdentifiersForClient: [[ISyncManager sharedManager] clientWithIdentifier: clientIdentifier]]];

    if (![[record objectForKey: RecordEntityName] isEqual: EntityContact]) {
      NSDictionary *contactRecords = [snapshot recordsWithIdentifiers: [record objectForKey: @"contact"]];
      
      if ([contactRecords count])
        contactRecord = [contactRecords objectForKey: [[contactRecords allKeys] objectAtIndex: 0]];
    } else
      contactRecord = record;

    /* verify that the contact has at least 1 email or phone number */
    numberRecords = [snapshot recordsWithIdentifiers: [contactRecord objectForKey: @"phone numbers"]];
    
    for (id numberUUID in [numberRecords allKeys]) {
      NSString *numberType = [[numberRecords objectForKey: numberUUID] objectForKey: @"type"];
      
      if ([numberType isEqualToString: @"mobile"] || [numberType isEqualToString: @"work"] ||
          [numberType isEqualToString: @"home"] || [numberType isEqualToString: @"home fax"])
        contactCanBeSynced = YES;
    }
    
    if (!syncOnlyWithPhoneNumbers && [[contactRecord objectForKey: @"email addresses"] count])
      contactCanBeSynced = YES;
    
    if (!contactCanBeSynced) {
      [[vxSyncLogger defaultLogger] addMessageWithLevel: VXSYNC_LOG_WARNING func: __func__ line: __LINE__ format: @"contact associated with record does not have any syncable emails/phone numbers and will not be synced: %s\n", [[record description] UTF8String]];
      return NO;
    }
    
    if ([contactRecord objectForKey: @"parent groups"]) {
      groupRecords = [snapshot recordsWithIdentifiers: [contactRecord objectForKey: @"parent groups"]];
      
      [[vxSyncLogger defaultLogger] addMessageWithLevel: VXSYNC_LOG_INFO func: __func__ line: __LINE__ format: @"groupRecords = %s\n", NS2CH(groupRecords)];
      
      for (id groupID in [groupRecords allKeys]) {
        NSString *name = [[groupRecords objectForKey: groupID] objectForKey: @"name"];

        if ([groupNames indexOfObject: name] != NSNotFound)
          return YES;
      }
    }
    
    return syncAllGroups;
  }
  
  return syncAllGroups || ([groupNames indexOfObject: [record objectForKey: @"name"]] != NSNotFound);
}

- (BOOL) isEqual: (id) anotherFilter {  
  if ([anotherFilter respondsToSelector: @selector(groupNames)])
    return [groupNames isEqual: [anotherFilter groupNames]] && syncAllGroups == [anotherFilter syncAllGroups];
  
  return NO;
}

#pragma mark NSCoding
- (id)initWithCoder:(NSCoder *)coder {
  if ( [coder allowsKeyedCoding] ) {
    [self setGroupNames: [coder decodeObjectForKey:@"groupNames"]];
    [self setClientIdentifier: [coder decodeObjectForKey:@"clientIdentifier"]];
    [self setSyncAllGroups: [[coder decodeObjectForKey: @"syncAllGroups"] boolValue]];
    [self setSyncOnlyWithPhoneNumbers: [[coder decodeObjectForKey: @"syncOnlyWithPhoneNumbers"] boolValue]];
  } else {
    [self setGroupNames: [coder decodeObject]];
    [self setClientIdentifier: [coder decodeObject]];
    [self setSyncAllGroups: [[coder decodeObject] boolValue]];
    [self setSyncOnlyWithPhoneNumbers: [[coder decodeObject] boolValue]];
  }
  
  snapshot = nil;
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  if ([coder allowsKeyedCoding]) {
    [coder encodeObject: groupNames forKey:@"groupNames"];
    [coder encodeObject: clientIdentifier forKey:@"clientIdentifier"];
    [coder encodeObject: [NSNumber numberWithBool: syncAllGroups] forKey: @"syncAllGroups"];
    [coder encodeObject: [NSNumber numberWithBool: syncOnlyWithPhoneNumbers] forKey: @"syncOnlyWithPhoneNumbers"];
  } else {
    [coder encodeObject: groupNames];
    [coder encodeObject: clientIdentifier];
    [coder encodeObject: [NSNumber numberWithBool: syncAllGroups]];
    [coder encodeObject: [NSNumber numberWithBool: syncOnlyWithPhoneNumbers]];
  }

  return;
}

@end
