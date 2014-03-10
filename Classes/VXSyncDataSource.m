/* (-*- objc -*-)
 * vxSync: VXSyncDataSource.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.8.5
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

#include "VXSync.h"
#include "BREWefs.h"

#include "VXSyncDataSource.h"
#include "VXSyncDataDelegate.h"
#include "vxSyncCalendarFilter.h"
#include <CalendarStore/CalendarStore.h>

@interface VXSyncDataSource (hidden)
- (int) commitChanges: (NSDictionary *) changes toSource: (id <LGData>) dataSource;
- (NSArray *) findRecordsRelatedTo: (NSDictionary *) record onPhone: (BOOL) onPhone;

- (void) loadPersistentStore;
- (void) writePersistentStore;

- (void) setRecurrenceEndDateFromCount: (NSMutableDictionary *) recurrence;
@end

static BOOL isOnPhone (id key, id obj, BOOL *stop) {
  return [[obj objectForKey: VXKeyOnPhone] boolValue];
}

static BOOL notOnPhone (id key, id obj, BOOL *stop) {
  return ![[obj objectForKey: VXKeyOnPhone] boolValue];
}

@implementation VXSyncDataSource

+ (id) dataSourceWithPhone: (vxPhone *) phoneIn {
  return [[[VXSyncDataSource alloc] initWithPhone: phoneIn] autorelease];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];
  if (!self)
    return nil;

  [self setPhone: phoneIn];
  /* don't do anything if there is nothing to sync */
  if (![[phone getOption: @"calendar.sync"] boolValue] &&
      ![[phone getOption: @"contacts.sync"] boolValue] &&
      ![[phone getOption: @"notes.sync"] boolValue]) {
    return nil;
  }

  if (([[phone getOption: @"calendar.sync"] boolValue] && VXSYNC_MODE_PHONE_OW == [[phone getOption: @"calendar.mode"] intValue]) ||
      ([[phone getOption: @"contacts.sync"] boolValue] && VXSYNC_MODE_PHONE_OW == [[phone getOption: @"contacts.mode"] intValue]) ||
      ([[phone getOption: @"notes.sync"] boolValue] && VXSYNC_MODE_PHONE_OW == [[phone getOption: @"notes.mode"] intValue])) {
    self.needsTwoPhaseSync = YES;
  } else
    self.needsTwoPhaseSync = NO;

  [self setBundle: vxSyncBundle ()];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"bundle = %s\n", NS2CH(bundle));
  vxSync_log3(VXSYNC_LOG_INFO, @"phone options = %s\n", NS2CH([phone options]));
  
  [self setSupportedEntities: [NSMutableDictionary dictionary]];
  [self setPhase: 1];
  [self setClient: [[ISyncManager sharedManager] clientWithIdentifier: [self clientIdentifier]]];

  [self loadPersistentStore];
  
  return self;
}

@synthesize sessionDriver, phone, bundle, phoneChanges, snapshot, dataSources, persistentStore, supportedEntities, client, phase, needsTwoPhaseSync;

- (void) dealloc {
  vxSync_log3(VXSYNC_LOG_INFO, @"dealloc called on VXSyncDataSource\n");
  
  [self setSessionDriver: nil];
  [self setPhone: nil];
  [self setBundle: nil];
  [self setPhoneChanges: nil];
  [self setSnapshot: nil];
  [self setDataSources: nil];
  [self setPersistentStore: nil];
  [self setSupportedEntities: nil];
  [self setClient: nil];
  
  [super dealloc];
}

- (NSString *)clientIdentifier {
  return [@"com.enansoft.vxSync." stringByAppendingString: [phone identifier]];
}

- (NSString *) clientDescriptionPath {
  return [phone clientDescriptionPath];
}

- (NSURL *)clientDescriptionURL {
  return [NSURL fileURLWithPath: [self clientDescriptionPath]];
}

/* (R) Returns an array containing NSURL objects representing the path to schemas this client uses. */
- (NSArray *) schemaBundleURLs {
//  return [bundle URLsForResourcesWithExtension: @"syncschema" subdirectory: nil];
  return [NSArray arrayWithObject: [NSURL fileURLWithPath: [bundle pathForResource: @"VXSyncSchema" ofType:@"syncschema"]]];
}

#pragma mark push phase
#pragma mark record changes
- (NSArray *) findChangesBetween: (NSDictionary *) oldRecord and: (NSDictionary *) newRecord {
  NSMutableArray *changes = [NSMutableArray array];
  NSMutableSet *allKeys = [NSMutableSet setWithArray: [oldRecord allKeys]];
  
  [allKeys unionSet: [NSSet setWithArray: [newRecord allKeys]]];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"new record: %s, old Record: %s\n", NS2CH(newRecord), NS2CH(oldRecord));
  
  for (id key in allKeys) {
    id newKeyData = [newRecord objectForKey: key];
    id oldKeyData = [oldRecord objectForKey: key];

    if (!newKeyData) {
      [changes addObject: [NSDictionary dictionaryWithObjectsAndKeys:
					  ISyncChangePropertyClear, ISyncChangePropertyActionKey,
					  key,                      ISyncChangePropertyNameKey,
					  nil]];
    } else if (!oldKeyData ||
               ([newKeyData isKindOfClass: [NSArray class]] && ![[NSSet setWithArray: newKeyData] isEqual: [NSSet setWithArray: oldKeyData]]) ||
               (![newKeyData isKindOfClass: [NSArray class]] && ![newKeyData isEqual: oldKeyData])) {
      [changes addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                           ISyncChangePropertySet,        ISyncChangePropertyActionKey,
                           key,                           ISyncChangePropertyNameKey,
                           [newRecord objectForKey: key], ISyncChangePropertyValueKey,
                           nil]];
    }
  }

  vxSync_log3(VXSYNC_LOG_DEBUG, @"changes: %s\n", NS2CH(changes));

  return [[changes copy] autorelease];
}

- (void) applyChanges: (NSDictionary *) changesDictionary {
  vxSync_log3(VXSYNC_LOG_DEBUG, @"self = %p, applying change(s) to the persistent store: %s\n", self, NS2CH(changesDictionary));
  
  for (id entityName in [changesDictionary allKeys]) {
    NSArray *changes = [changesDictionary objectForKey: entityName];
    
    for (ISyncChange *change in changes) {
      NSMutableDictionary *newDictionary = nil;
      
      switch ([change type]) {
        case ISyncChangeTypeModify:
          newDictionary = [[[self removeRecordWithIdentifier: [change recordIdentifier] withEntityName: entityName] mutableCopy] autorelease];
        case ISyncChangeTypeAdd:
          if (!newDictionary)
            newDictionary = [NSMutableDictionary dictionary];
          
          for (id recordChange in [change changes]) {
            NSString *action = [recordChange objectForKey: ISyncChangePropertyActionKey];
            NSString *key    = [recordChange objectForKey: ISyncChangePropertyNameKey];
            NSString *value  = [recordChange objectForKey: ISyncChangePropertyValueKey];
            
            if ([action isEqual: ISyncChangePropertySet] || [action isEqual: ISyncChangePropertyClear])
              [newDictionary setValue: value forKey: key];
            else
              vxSync_log3(VXSYNC_LOG_WARNING, @"unsupported change action: %s\n", NS2CH(action));
          }

          [self addRecord: [newDictionary copy] withIdentifier: [change recordIdentifier] withEntityName: entityName];
          
          break;
        case ISyncChangeTypeDelete:
          (void) [self removeRecordWithIdentifier: [change recordIdentifier] withEntityName: entityName];
          break;
        default:
          vxSync_log3(VXSYNC_LOG_WARNING, @"unsupported change type: %i\n", [change type]);
      }
    }
  }
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"persistent store after changes: %s\n", NS2CH(persistentStore));
}

- (int) updateRelation: (NSString *) relation reverseRelation: (NSString *) reverseRelation forRecord: (NSMutableDictionary *) record
            entityName: (NSString *) entityName {
  NSString *recordIdentifier = [record objectForKey: VXKeyIdentifier];
  NSDictionary *oldRecord = [[persistentStore objectForKey: [record objectForKey: RecordEntityName]] objectForKey: recordIdentifier];
  NSArray *oldRelations = [oldRecord objectForKey: relation];
  /* passing nil or an empty array to setWithArray *should* work */
  NSMutableSet *uuids = [NSMutableSet setWithArray: [record objectForKey: relation]];
  NSString *syncedRelationKey = [NSString stringWithFormat: @"com.enansoft.vxSync.%@", reverseRelation];

  vxSync_log3(VXSYNC_LOG_DEBUG, @"old relations for record = %s\n", NS2CH(oldRelations));

  if (![persistentStore objectForKey: entityName] && oldRelations) {
    /* keep the relation if we don't sync the relation type */
    [record setObject: oldRelations forKey: relation];
    
    return 0;
  }
  
  for (id identifier in oldRelations) {
    NSDictionary *relatedObject = [self findRecordWithIdentifier: identifier entityName: entityName];
    BOOL onPhone = [[relatedObject objectForKey: VXKeyOnPhone] boolValue];
    /* only pertains to parent groups at the moment */
    NSArray *syncedRelations = [relatedObject objectForKey: syncedRelationKey];

    if (!onPhone || (syncedRelations && ([syncedRelations indexOfObject: identifier] == NSNotFound)))
      [uuids addObject: identifier];
  }

  /* make sure all related objects actually exist */
  [uuids intersectSet: [NSSet setWithArray: [[persistentStore objectForKey: entityName] allKeys]]];

  vxSync_log3(VXSYNC_LOG_DEBUG, @"setting relations to: %s\n", NS2CH(uuids));
  if ([uuids count])
    [record setValue: [uuids allObjects] forKey: relation];
  else
    [record removeObjectForKey: relation];

  return 0;
}

- (void) finishContact: (NSMutableDictionary *) contactRecord {
  NSDictionary *oldRecord = [[persistentStore objectForKey: EntityContact] objectForKey: [contactRecord objectForKey: VXKeyIdentifier]];
  NSMutableArray *parentGroups = [NSMutableArray array];

  vxSync_log3(VXSYNC_LOG_DEBUG, @"finishing arrays for contact: %s\n", NS2CH(contactRecord));
  
  /* add back non-synced emails */
  [self updateRelation: @"email addresses" reverseRelation: @"contact" forRecord: contactRecord entityName: EntityEmail];
  [self updateRelation: @"street addresses" reverseRelation: @"contact" forRecord: contactRecord entityName: EntityAddress];
  [self updateRelation: @"phone numbers" reverseRelation: @"contact" forRecord: contactRecord entityName: EntityNumber];
  [self updateRelation: @"IMs" reverseRelation: @"contact" forRecord: contactRecord entityName: EntityIM];

  if ([oldRecord objectForKey: VXKeyOnPhoneGroups]) {
    /* 0.5.1+ */
    NSMutableSet *deleted = [NSMutableSet setWithArray: [oldRecord objectForKey: VXKeyOnPhoneGroups]];
    NSMutableSet *added   = [NSMutableSet setWithArray: [contactRecord objectForKey: VXKeyOnPhoneGroups]];
    
    /* the set of synced groups has changed. the contact will need to be resynced */
    if (![added isEqualToSet: deleted])
      [contactRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyDirty];

    vxSync_log3(VXSYNC_LOG_DEBUG, @"old synced groups = %s\n", NS2CH(deleted));
    vxSync_log3(VXSYNC_LOG_DEBUG, @"new synced groups = %s\n", NS2CH(added));
    
    [added minusSet: [NSSet setWithArray: [oldRecord objectForKey: VXKeyOnPhoneGroups]]];
    [deleted minusSet: [NSSet setWithArray: [contactRecord objectForKey: VXKeyOnPhoneGroups]]];

    [parentGroups addObjectsFromArray: [oldRecord objectForKey: @"parent groups"]];
    vxSync_log3(VXSYNC_LOG_DEBUG, @"old parent groups = %s\n", NS2CH(parentGroups));

    [parentGroups removeObjectsInArray: [deleted allObjects]];
    [parentGroups addObjectsFromArray: [added allObjects]];

    vxSync_log3(VXSYNC_LOG_DEBUG, @"new parent groups = %s\n", NS2CH(parentGroups));
  } else
    [parentGroups addObjectsFromArray: [contactRecord objectForKey: @"parent groups"]];

  [contactRecord setObject: parentGroups forKey: @"parent groups"];
}

- (void) finishEvent: (NSMutableDictionary *) eventRecord {
  vxSync_log3(VXSYNC_LOG_DEBUG, @"finishing relationship arrays for event: %s\n", NS2CH(eventRecord));
  
  [self updateRelation: @"display alarms" reverseRelation: @"owner" forRecord: eventRecord entityName: EntityDisplayAlarm];
  [self updateRelation: @"audio alarms" reverseRelation: @"owner" forRecord: eventRecord entityName: EntityAudioAlarm];
  if ([eventRecord objectForKey: @"exceptions"]) {
    NSSet *exceptions = [NSSet setWithArray: [eventRecord objectForKey: @"exceptions"]];
    /* delete duplicate exceptions -- prevent exception blow-up */
    [eventRecord setObject: [exceptions allObjects] forKey: @"exceptions"];
  }
}

- (void) finishGroup: (NSMutableDictionary *) groupRecord {
  vxSync_log3(VXSYNC_LOG_DEBUG, @"finishing relationship arrays for group: %s\n", NS2CH(groupRecord));
  [self updateRelation: @"members" reverseRelation: @"parent groups" forRecord: groupRecord entityName: EntityContact];
}

- (void) finishCalendar: (NSMutableDictionary *) calendarRecord {
  vxSync_log3(VXSYNC_LOG_DEBUG, @"finishing relationship arrays for calendar: %s\n", NS2CH(calendarRecord));
  [self updateRelation: @"events" reverseRelation: @"calendar" forRecord: calendarRecord entityName: EntityEvent];
}

- (NSDictionary *) loadChanges {
  NSMutableDictionary *changesDictionary = [NSMutableDictionary dictionary];
  id identifier, record, recordChanges;
  NSDictionary *objects;
  NSSet *oldOnPhone;
  NSMutableSet *deletedRecords;
  NSMutableArray *changes;

  if (needsTwoPhaseSync && 1 == phase)
    return changesDictionary;

  for (id dataSourceDict in [dataSources allValues]) {
    id dataSource = [dataSourceDict valueForKeyPath: @"dataSource"];
    int mode = [[dataSourceDict valueForKeyPath: @"mode"] intValue];
    
    objects = [dataSource readRecords];
    
    printf ("Evaluating phone data\n");

    for (id entityName in objects) {
      oldOnPhone = (VXSYNC_MODE_PHONE_OW == mode) ? [NSSet setWithArray: [[persistentStore objectForKey: entityName] allKeys]] : [[persistentStore objectForKey: entityName] keysOfObjectsPassingTest: isOnPhone];
      deletedRecords = [[oldOnPhone mutableCopy] autorelease];
      changes = [NSMutableArray array];
      
      [deletedRecords minusSet: [NSSet setWithArray: [[objects objectForKey: entityName] allKeys]]];

      for (identifier in deletedRecords)
        [changes addObject: [ISyncChange changeWithType: ISyncChangeTypeDelete recordIdentifier: identifier changes: nil]];

      for (identifier in [objects objectForKey: entityName]) {
        record = [[[[objects objectForKey: entityName] objectForKey: identifier] mutableCopy] autorelease];
        [record setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];

        if ([entityName isEqualToString: EntityGroup])
          [self finishGroup: record];
        else if ([entityName isEqualToString: EntityContact])
          [self finishContact: record];
        else if ([entityName isEqualToString: EntityCalendar])
          [self finishCalendar: record];
        else if ([entityName isEqualToString: EntityEvent])
          [self finishEvent: record];
        
        recordChanges = [self findChangesBetween: [self findRecordWithIdentifier: identifier entityName: entityName] and: record];

        if (![self findRecordWithIdentifier: identifier entityName: entityName])
          [changes addObject: [ISyncChange changeWithType: ISyncChangeTypeAdd recordIdentifier: identifier changes: recordChanges]];
        else if ([recordChanges count])
          [changes addObject: [ISyncChange changeWithType: ISyncChangeTypeModify recordIdentifier: identifier changes: recordChanges]];
      }
      
      [changesDictionary setObject: [[changes copy] autorelease] forKey: entityName];
    }
  }

  return [[changesDictionary copy] autorelease];
}

#pragma mark slow sync
/* (R) Returns records for the given entity name that should be pushed to the sync engine during a slow sync. */
- (NSDictionary *) recordsForEntityName: (NSString *) entityName moreComing:(BOOL *)moreComing error:(NSError **)outError {
  NSMutableDictionary *records = [[[persistentStore objectForKey: entityName] mutableCopy] autorelease];
  NSSet *fixDateObjects = [NSSet setWithObjects: @"start date", @"end date", @"until", @"original date", nil];
  NSArray *identifiers;

  identifiers = [records allKeys];

  vxSync_log3(VXSYNC_LOG_INFO, @"self = %p, for entityName: %s, allKeys: %s\n", self, NS2CH(entityName), NS2CH(identifiers));

  for (NSString *identifier in identifiers) {
    NSMutableDictionary *newEntry = [[[records objectForKey: identifier] mutableCopy] autorelease];
    NSArray *keys = [newEntry allKeys];

    /* remove all internal keys (these keys are phone-specific for now) */
    for (id key in keys) {
      if ([key hasPrefix: @"com.enansoft.vxSync"])
        [newEntry removeObjectForKey: key];
      else if ([fixDateObjects member: key])
        [newEntry setObject: [[newEntry objectForKey: key] dateWithCalendarFormat: nil timeZone: nil] forKey: key];
    }
    
    [records setObject: [NSDictionary dictionaryWithDictionary: newEntry] forKey: identifier];
  }
  
  vxSync_log3(VXSYNC_LOG_INFO, @"returning records: %s\n", NS2CH(records));
  
  *moreComing = NO;
  return [[records copy] autorelease];
}

#pragma mark fast sync
/* (R for fast sync) */
- (NSArray *) changesForEntityName: (NSString *) entity moreComing: (BOOL *) moreComing error: (NSError **) outError {
  NSMutableArray *entityChanges = [NSMutableArray array];
  *moreComing = NO;

  vxSync_log3(VXSYNC_LOG_INFO, @"entering...\n");

  for (ISyncChange *changes in [phoneChanges objectForKey: entity]) {
    NSMutableArray *changeArray = [NSMutableArray array];

    /* remove all changes to internal keys (these keys are phone-specific for now) */
    for (id change in [changes changes])
      if (![[change objectForKey: ISyncChangePropertyNameKey] hasPrefix: @"com.enansoft.vxSync"])
        [changeArray addObject: change];

    if ([changeArray count] > 0 || [changes type] == ISyncChangeTypeDelete)
      [entityChanges addObject: [ISyncChange changeWithType: [changes type] recordIdentifier: [changes recordIdentifier] changes: [[changeArray copy] autorelease]]];
  }

  vxSync_log3(VXSYNC_LOG_DEBUG, @"entityChanges for %s = %s\n", NS2CH(entity), NS2CH(entityChanges));
  
  return [[entityChanges copy] autorelease];
}
/***** end: fast sync *****/

#pragma mark pull phase
- (ISyncSessionDriverChangeResult) applyChange:(ISyncChange *)change
                                 forEntityName:(NSString *)entityName
                      remappedRecordIdentifier:(NSString **)outRecordIdentifier
                               formattedRecord:(NSDictionary **)outRecord
                                         error:(NSError **)outError {
  id <LGData> dataSource;
  NSDictionary *formattedRecord = nil, *changeRecord = nil;
  NSMutableDictionary *cleanRecord;
  NSString *changeIdentifier;
  NSDictionary *oldRecord = nil;
  
  changeRecord = [change record];
  changeIdentifier = [change recordIdentifier];

  dataSource = [[dataSources objectForKey: [supportedEntities objectForKey: entityName]] valueForKeyPath: @"dataSource"];
  
  if (!dataSource)
    /* entity not supported or disabled */
    return ISyncSessionDriverChangeIgnored;
  
  if ([change type] != ISyncChangeTypeDelete) {
    NSMutableDictionary *newRecord;
    
    newRecord = [[changeRecord mutableCopy] autorelease];

    vxSync_log3(VXSYNC_LOG_DEBUG, @"incomming record: %s\n", NS2CH(newRecord));
    
    if ([change type] == ISyncChangeTypeModify) {
      oldRecord = [self removeRecordWithIdentifier: changeIdentifier withEntityName: entityName];

      /* copy our keys from the dictionary */
      for (id key in [oldRecord allKeys])
        if ([key hasPrefix: @"com.enansoft"])
          [newRecord setObject: [oldRecord objectForKey: key] forKey: key];
    } else if ([change type] != ISyncChangeTypeAdd)
      /* unknown change type */
      return ISyncSessionDriverChangeIgnored;    
    
    vxSync_log3(VXSYNC_LOG_DEBUG, @"new/modified record: %s\n", NS2CH(newRecord));

    /* the record has changed and needs to be updated on the phone */
    if ([[newRecord objectForKey: VXKeyOnPhone] boolValue])
      [newRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyDirty];
    if ([[newRecord objectForKey: ISyncRecordEntityNameKey] isEqualToString: EntityRecurrence] &&
        [newRecord objectForKey: @"count"] && ![newRecord objectForKey: @"until"]) {
      /* need to set the end data */
      [self setRecurrenceEndDateFromCount: newRecord];
    }

    /* ask the datasource to format this record (to tell the sync engine how we will represent this record) */
    formattedRecord = [dataSource formatRecord: newRecord identifier: changeIdentifier];

    [self addRecord: formattedRecord withIdentifier: changeIdentifier withEntityName: entityName];

    /* clean out our keys */
    cleanRecord = [[formattedRecord mutableCopy] autorelease];
    for (id key in [formattedRecord allKeys])
      if ([key hasPrefix: @"com.enansoft.vxSync"])
        [cleanRecord removeObjectForKey: key];

    vxSync_log3(VXSYNC_LOG_DEBUG, @"formatted record: %s\n", NS2CH(formattedRecord));
    
    *outRecord = [[cleanRecord copy] autorelease];  
  } else {    
    formattedRecord = [self removeRecordWithIdentifier: changeIdentifier withEntityName: entityName];
    if ([[formattedRecord objectForKey: VXKeyOnPhone] boolValue]) {
      if ([dataSource deleteRecord: formattedRecord] == -1)
        return ISyncSessionDriverChangeError;
    }
  }
  
  return ISyncSessionDriverChangeAccepted;
}

/* (R) Deletes all records for the specified entity. */
- (BOOL) deleteAllRecordsForEntityName: (NSString *)entityName error:(NSError **)outError {
  id <LGData> dataSource = [[dataSources objectForKey: [supportedEntities objectForKey: entityName]] valueForKeyPath: @"dataSource"];

  if ([dataSource deleteAllRecordsForEntityName: entityName]) {
    [persistentStore removeObjectForKey: entityName];

    return YES;
  }

  return NO;
}

/* (O) Returns an array of NSString objects representing the names of entities this client wants to pull. */
- (NSArray *)entityNamesToPull {
  return [supportedEntities allKeys];
}

/* (O) Returns an array of NSString objects representing the names of entities this client wants to sync. */
- (NSArray *)entityNamesToSync {
  return [supportedEntities allKeys];
}

/* (R) Returns the client's preferred sync mode for the session. */
- (ISyncSessionDriverMode) preferredSyncModeForEntityName: (NSString *) entity {
  NSDictionary *tmp = [dataSources objectForKey: [supportedEntities objectForKey: entity]];
  int mode = [[tmp objectForKey: @"mode"] intValue];
  int syncMode;
  
  if (!tmp)
    /* this should NEVER happen! */
    return 0;
  
  switch (mode) {
    case VXSYNC_MODE_MERGE:
      syncMode = [persistentStore objectForKey: entity] ? ISyncSessionDriverModeFast : ISyncSessionDriverModeSlow;
      
      break;
    case VXSYNC_MODE_COMPUTER_OW:
      syncMode = ISyncSessionDriverModeRefresh;
      
      break;
    case VXSYNC_MODE_PHONE_OW:
      syncMode = (1 == phase) ? ISyncSessionDriverModeRefresh : ISyncSessionDriverModeFast;
      
      break;
    default:
      return 0;
  }

  vxSync_log3(VXSYNC_LOG_INFO, @"self = %p, returning syncMode %i (mode = %i, phase = %i) for %s\n", self, syncMode, mode, phase, NS2CH(entity));
  return syncMode;
}

/* helper methods */
- (int) setupDataSource: (id <LGData>) dataSource mode: (int) mode {
  NSArray *entities = [dataSource supportedEntities];
  
  if ((needsTwoPhaseSync && 1 == phase) && VXSYNC_MODE_PHONE_OW != mode)
    /* do nothing */
    return 0;

  [dataSource setDelegate: self];
  
  if (VXSYNC_MODE_COMPUTER_OW == mode)
    [dataSource deleteAllRecords];

  for (id entity in entities)
    [supportedEntities setObject: [dataSource dataSourceIdentifier] forKey: entity];

  NSDictionary *tmp = [NSDictionary dictionaryWithObjectsAndKeys: dataSource, @"dataSource", [NSNumber numberWithInt: mode], @"mode", nil];
  [dataSources setObject: tmp forKey: [dataSource dataSourceIdentifier]];

  return 0;
}

- (NSDate *) determineNextEventOccurenceForEvent: (NSDictionary *) event after: (NSDate *) date recurrences: (NSDictionary *) recurrences {
  NSDictionary *recurrence = nil;

  vxSync_log3(VXSYNC_LOG_DEBUG, @"determining next occurence of event: %s\n", NS2CH(event));

  if ([[event objectForKey: @"recurrences"] count])
    recurrence = [recurrences objectForKey: [[event objectForKey: @"recurrences"] objectAtIndex: 0]];

  return getAnOccurrence (event, recurrence, date);
}

- (void) setRecurrenceEndDateFromCount: (NSMutableDictionary *) recurrence {
  NSDictionary *eventSnapshot, *event;
  NSDate *occurrence = nil;
  
  /* get a snapshot of the truth for this session */
  if (!snapshot)
    [self setSnapshot: [[ISyncManager sharedManager] snapshotOfRecordsInTruthWithEntityNames: [NSArray arrayWithObjects: EntityEvent, EntityRecurrence, nil] usingIdentifiersForClient: client]];

  eventSnapshot      = [snapshot recordsWithMatchingAttributes: [NSDictionary dictionaryWithObject: EntityEvent forKey: RecordEntityName]];
  event              = [eventSnapshot objectForKey: [[recurrence objectForKey: @"owner"] objectAtIndex: 0]];

  vxSync_log3(VXSYNC_LOG_DEBUG, @"trying to determing actual end date of: %s\n", NS2CH(recurrence));
  
  occurrence = getAnOccurrence (event, recurrence, nil);
  if (!occurrence) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"could not determine last occurrence for count recurrence: %s\n", NS2CH(recurrence));
    /* can't determine last occurence */
    return;
  }
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"last occurence or recurrence appears to be on %s\n", NS2CH(occurrence)); 

  [recurrence removeObjectForKey: @"count"];
  [recurrence setObject: [occurrence dateWithCalendarFormat: nil timeZone: nil] forKey: @"until"];
}

#pragma mark save data to phone
- (int) commitCalendarsAndEventsTo: (id <LGData>) dataSource {
  NSArray *calendars        = [[persistentStore objectForKey: EntityCalendar] allValues];
  NSDictionary *events      = [persistentStore objectForKey: EntityEvent];
  NSDictionary *recurrences = [persistentStore objectForKey: EntityRecurrence];

  NSMutableArray *syncArray, *allEventsOrdered = [NSMutableArray array];
  NSDictionary *changes = [NSDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"delete", [NSMutableArray array], @"modify", nil];
  BOOL calIsLimited = [[phone getOption: @"calendar.isLimited"] boolValue];
  NSDate *limitDate = [phone getOption: @"calendar.limitDate"];
  int eventThreshold = (int)([[phone getOption: @"calendar.eventThreshold"] floatValue] * 100.0);

  int eventLimit;

  if (!eventThreshold) eventThreshold = 95;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"commiting events = %s\n", NS2CH(events));
  
  /* replace all calendars on phone */
  [dataSource deleteAllRecordsForEntityName: EntityCalendar];
  [[changes objectForKey: @"modify"] addObjectsFromArray: calendars];

  /* now uses a "smarter" ordering. as an event gets older it becomes 6 times less likely to be synced -- fixed */
  for (id identifier in [events allKeys]) {
    NSDictionary *record = [events objectForKey: identifier];
    NSDate *nextDate = [self determineNextEventOccurenceForEvent: record after: [NSDate date] recurrences: recurrences];
    int interval     = [nextDate timeIntervalSinceNow]/3600;

    vxSync_log3(VXSYNC_LOG_DEBUG, @"next occurrence date of %s: %s is of type %s\n", NS2CH(record), NS2CH(nextDate), NS2CH([nextDate class]));

    if (!nextDate || (calIsLimited && [nextDate compare: limitDate] == NSOrderedAscending)) {
      if ([[record objectForKey: VXKeyOnPhone] boolValue])
        [[changes objectForKey: @"delete"] addObject: record];
      continue;
    }

    if (interval < 0)
      interval *= -6;

    [allEventsOrdered addObject: [NSDictionary dictionaryWithObjectsAndKeys: identifier, VXKeyIdentifier, [NSNumber numberWithInt: interval], @"hoursAway", nil]];
  }
  
  [allEventsOrdered sortUsingFunction: sortAscending context: @"hoursAway"];
  
  /* keep user specified % of the event space free for new events */
  eventLimit = ([phone limitForEntity: EntityEvent] * eventThreshold)/100;

  syncArray = [allEventsOrdered mapSelector: @selector(objectForKey:) withObject: VXKeyIdentifier];
  vxSync_log3(VXSYNC_LOG_INFO, @"count = %i, limit = %i\n", [syncArray count], eventLimit);
  if ([syncArray count] > eventLimit)
    [syncArray removeObjectsInRange: NSMakeRange (eventLimit, [syncArray count] - eventLimit)];

  vxSync_log3(VXSYNC_LOG_INFO, @"sync event count = %i\n", [syncArray count]);
  
  for (id orderedIdentifier in allEventsOrdered) {
    id identifier = [orderedIdentifier objectForKey: VXKeyIdentifier];
    NSDictionary *record = [events objectForKey: identifier];
    NSArray *relatedRecordsOnPhone = [self findRecordsRelatedTo: record onPhone: YES];
    BOOL onPhone = [[record objectForKey: VXKeyOnPhone] boolValue];
        
    vxSync_log3(VXSYNC_LOG_DEBUG, @"checking event record: %s\n", NS2CH(record));
    
    if ([syncArray indexOfObject: identifier] == NSNotFound) {
      if (onPhone) {
        [[changes objectForKey: @"delete"] addObjectsFromArray: relatedRecordsOnPhone];
        [[changes objectForKey: @"delete"] addObject: record];
      }
    } else {
      BOOL isDirty = !onPhone;

      if (onPhone) {
        isDirty  = [[record objectForKey: VXKeyDirty] boolValue];
        
        for (id relatedObject in relatedRecordsOnPhone)
          isDirty |= [[relatedObject objectForKey: VXKeyDirty] boolValue];
      }
      
      if (isDirty)
        [[changes objectForKey: @"modify"] addObject: record];
    }
  }
  
  return [self commitChanges: changes toSource: dataSource];
}

- (NSArray *) findRecordsRelatedTo: (NSDictionary *) record onPhone: (BOOL) onPhone {
  NSMutableArray *records = [NSMutableArray array];
  NSArray *entityNames = [persistentStore allKeys];
  NSMutableArray *identifiers = [NSMutableArray array];
  
  for (id key in [record allKeys]) {
    /* ignore parent relations */
    if ([key isEqual: @"parent group"] || [key isEqual: @"calendar"] || [key isEqual: @"owner"] || [key isEqual: @"contact"])
      continue;

    if ([key isEqualToString: @"exception dates"] || ![[record objectForKey: key] isKindOfClass: [NSArray class]])
      continue;

    [identifiers addObjectsFromArray: [record objectForKey: key]];
  }
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"related identifiers: %s\n", NS2CH(identifiers));
  
  for (id identifier in identifiers) {
    id entityName, relatedRecord;
    
    for (entityName in entityNames) {
      relatedRecord = [[persistentStore objectForKey: entityName] objectForKey: identifier];
      if (relatedRecord)
        break;
    }
    
    if (!relatedRecord) {
      vxSync_log3(VXSYNC_LOG_WARNING, @"could not find record: %s\n", NS2CH(identifier));
      continue;
    }

    if ([[relatedRecord objectForKey: VXKeyOnPhone] boolValue] == onPhone)
      [records addObject: relatedRecord];
  }
  
  return records;
}

- (int) commitGenericTo: (id <LGData>) dataSource entityNames: (NSArray *) entityNames {
  NSMutableArray *syncRecords =[ NSMutableArray array];
  NSDictionary *changes = [NSDictionary dictionaryWithObjectsAndKeys: [NSMutableArray array], @"delete", [NSMutableArray array], @"modify", nil];

  vxSync_log3(VXSYNC_LOG_INFO, @"commiting entities: %s\n", NS2CH(entityNames));
  
  for (NSString *entityName in entityNames) {
    NSDictionary *records = [persistentStore objectForKey: entityName];
    
    /* leave 5% of the phone's memory available for additions -- TODO -- make this configurable */
    int recordLimit = ([phone limitForEntity: entityName] * 95) / 100;
    
    NSSet *onPhoneRecords  = [records keysOfObjectsPassingTest: isOnPhone];
    NSSet *offPhoneRecords = [records keysOfObjectsPassingTest: notOnPhone];
    
    [syncRecords removeAllObjects];
    [syncRecords addObjectsFromArray: (NSArray *)onPhoneRecords];
    [syncRecords addObjectsFromArray: (NSArray *)offPhoneRecords];
    
    if ([syncRecords count] > recordLimit)
      [syncRecords removeObjectsInRange: NSMakeRange(recordLimit, [syncRecords count] - recordLimit)];
    
    for (id identifier in onPhoneRecords) {
      id record = [records objectForKey: identifier];     
      NSArray *relatedRecordsOnPhone = [self findRecordsRelatedTo: record onPhone: YES];
      
      if ([syncRecords indexOfObject: identifier] != NSNotFound) {
        BOOL isDirty = [[record objectForKey: VXKeyDirty] boolValue];

        /* check if any relationed objects have have changed */
        for (id relatedObject in relatedRecordsOnPhone)
          isDirty |= [[relatedObject objectForKey: VXKeyDirty] boolValue];
        
        if (isDirty)
          [[changes objectForKey: @"modify"] addObject: record];
      } else {
        [[changes objectForKey: @"delete"] addObject: record];
        [[changes objectForKey: @"delete"] addObjectsFromArray: relatedRecordsOnPhone];
      }
    }
    
    for (id identifier in offPhoneRecords)
      if ([syncRecords indexOfObject: identifier] != NSNotFound)
        [[changes objectForKey: @"modify"] addObject: [records objectForKey: identifier]];
  }
  
  return [self commitChanges: changes toSource: dataSource];
}

- (int) commitChanges: (NSDictionary *) changes toSource: (id <LGData>) dataSource {
  NSMutableDictionary *updatedRecord;

  for (id record in [changes objectForKey: @"delete"]) {
    updatedRecord = [[record mutableCopy] autorelease];
    [updatedRecord removeObjectForKey: VXKeyOnPhone];
    [self modifyRecord: updatedRecord withIdentifier: [updatedRecord objectForKey: VXKeyIdentifier] withEntityName:[updatedRecord objectForKey: RecordEntityName]];
 
    [dataSource deleteRecord: record];
    vxSync_log3(VXSYNC_LOG_INFO, @"removed record from phone: %s\n", NS2CH(record));
  }
  
  for (id record in [changes objectForKey: @"modify"]) {
    NSString *identifier = [record objectForKey: VXKeyIdentifier];
    NSDictionary *formattedRecord = nil;
    int ret;

    vxSync_log3(VXSYNC_LOG_INFO, @"adding/modifying record on phone: %s\n", NS2CH(record));
    if ([[record objectForKey: VXKeyOnPhone] boolValue])
      ret = [dataSource modifyRecord: record formattedRecordOut: &formattedRecord identifier: identifier];
    else
      ret = [dataSource addRecord: record formattedRecordOut: &formattedRecord identifier: identifier];

    if (0 == ret) {
      updatedRecord = [[(formattedRecord ? formattedRecord : record) mutableCopy] autorelease];
      [updatedRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];
      [self modifyRecord: updatedRecord withIdentifier: identifier withEntityName: [record objectForKey: RecordEntityName]];
    }
  }
  
  return 0;
}

/* delegate methods */
- (BOOL) sessionDriver:(ISyncSessionDriver *)sender didRegisterClientAndReturnError:(NSError **)outError {
  [self setDataSources: [NSMutableDictionary dictionary]];
  
  if ([[phone getOption: @"notes.sync"] boolValue])
    [self setupDataSource: [LGMemos sourceWithPhone: phone]
                     mode: [[phone getOption: @"notes.mode"] intValue]];

  if ([[phone getOption: @"calendar.sync"] boolValue])
    [self setupDataSource: [LGCalendar sourceWithPhone: phone]
                     mode: [[phone getOption: @"calendar.mode"] intValue]];

  if ([[phone getOption: @"contacts.sync"] boolValue])
    [self setupDataSource: [LGPhonebook sourceWithPhone: phone]
                     mode: [[phone getOption: @"contacts.mode"] intValue]];

  return YES;
}

/*
  - (BOOL)sessionDriver:(ISyncSessionDriver *)sender willPushAndReturnError:(NSError **)outError

  Happens before changesForEntityName:... or recordsForEntityName:...

  Load data from enabled data sources and commit the changes to the persistent store.
*/
- (BOOL)sessionDriver:(ISyncSessionDriver *)sender willPushAndReturnError:(NSError **)outError {  
  /* load changes from phone before pushing */
  for (id entityName in [supportedEntities allKeys]) {
    if (![persistentStore objectForKey: entityName] || [self preferredSyncModeForEntityName: entityName] == ISyncSessionDriverModeRefresh)
      [persistentStore setObject: [NSMutableDictionary dictionary] forKey: entityName];
  }
  
  phoneChanges = [[self loadChanges] retain];
  [self applyChanges: phoneChanges];
  
  return YES;
}

/* 
   - (BOOL) sessionDriver: (ISyncSessionDriver *) sender didPullAndReturnError: (NSError **) outError

   Happens after applyChange:...

   Now that all records are known determine which records will be stored (or kept)
   on the phone.
*/
- (BOOL) sessionDriver: (ISyncSessionDriver *) sender didPullAndReturnError: (NSError **) outError {
  id <LGData> dataSource;
  NSDictionary *tmp;
  
  if (!needsTwoPhaseSync || 2 == phase) {
    vxSync_log3(VXSYNC_LOG_INFO, @"pushing changes to phone: %s\n", NS2CH(persistentStore));
    
    tmp = [dataSources objectForKey: [supportedEntities objectForKey: EntityCalendar]];
    dataSource = [tmp valueForKeyPath: @"dataSource"];
    if (dataSource) {
      printf ("Writing calendar entries\n");
      [self commitCalendarsAndEventsTo: dataSource];
    }
    
    tmp = [dataSources objectForKey: [supportedEntities objectForKey: EntityContact]];
    dataSource = [tmp valueForKeyPath: @"dataSource"];
    if (dataSource) {
      printf ("Writing phonebook\n");
      
      /* groups must be committed to the phone before contacts or some parent groups will not be synced */
      [self commitGenericTo: dataSource entityNames: [NSArray arrayWithObject: EntityGroup]];
      [self commitGenericTo: dataSource entityNames: [NSArray arrayWithObject: EntityContact]];
    }
    
    tmp = [dataSources objectForKey: [supportedEntities objectForKey: EntityNote]];
    dataSource = [tmp valueForKeyPath: @"dataSource"];
    if (dataSource) {
      printf ("Writing notes\n");
      [self commitGenericTo: dataSource entityNames: [NSArray arrayWithObject: EntityNote]];
    }
    
    printf ("Finishing...\n");
  }

  return YES;
}

- (BOOL) sessionDriver: (ISyncSessionDriver *) sender didPushAndReturnError: (NSError **) outError {
  if (needsTwoPhaseSync && 1 == phase)
    [[NSUserDefaults standardUserDefaults] setPersistentDomain: persistentStore forName: [self clientIdentifier]];
  
  return YES;
}

/*
  - (void) sessionDriverDidFinishSession: (ISyncSessionDriver *) sender
  
  Last stage of the sync

  Actually commit changes to the phone now.
*/
- (void) sessionDriverDidFinishSession: (ISyncSessionDriver *) sender {
  if (needsTwoPhaseSync && 1 == phase) {
    /* do nothing. its up to the caller to start phase 2 */
    return;
  }
  
  for (id dataSource in [dataSources allValues])
    /* todo -- check return codes */
    (void) [[dataSource valueForKeyPath: @"dataSource"] commitChanges];

  [self writePersistentStore];
}

- (void) writePersistentStore {
  vxSync_log3(VXSYNC_LOG_DEBUG, @"writing persistent store to NSUserDefaults: %s\n", NS2CH(persistentStore));
  NSArray *entityNames = [persistentStore allKeys];

  /* clear dirty bits */
  for (id entityName in entityNames) {
    NSArray *recordIdentifiers = [[persistentStore objectForKey: entityName] allKeys];
    
    for (id recordIndentifer in recordIdentifiers) {
      NSMutableDictionary *record = [[[[persistentStore objectForKey: entityName] objectForKey: recordIndentifer] mutableCopy] autorelease];
      [record removeObjectForKey: VXKeyDirty];
      [[persistentStore objectForKey: entityName] setObject: record forKey: recordIndentifer];
    }
  }
  
  /* commit persistent store to disk */  
  [[NSUserDefaults standardUserDefaults] setPersistentDomain: persistentStore forName: [self clientIdentifier]];
}

- (void) loadPersistentStore {
  NSSet *fixDateObjects = [NSSet setWithObjects: @"start date", @"end date", @"until", @"original date", nil];
  
  [self setPersistentStore: [[[[NSUserDefaults standardUserDefaults] persistentDomainForName: [self clientIdentifier]] mutableCopy] autorelease]];
  if (![self persistentStore])
    [self setPersistentStore: [NSMutableDictionary dictionary]];

  for (id key in [persistentStore allKeys]) {
    NSDictionary *loadedRecords = [persistentStore objectForKey: key];
    NSMutableDictionary *fixedRecords = [NSMutableDictionary dictionary];
    
    for (id uuid in [loadedRecords allKeys]) {
      /* make mutable copies of all records */
      NSDictionary *originalRecord = [loadedRecords objectForKey: uuid];
      NSMutableDictionary *record = [[originalRecord mutableCopy] autorelease];
      
      /* NSCalendarDate gets stored as NSDate so we need to fix some properties here */
      for (id key in [originalRecord allKeys]) {
        if ([fixDateObjects member: key])
          [record setObject: [[record objectForKey: key] dateWithCalendarFormat: nil timeZone: nil] forKey: key];
      }
      
      /* fix exception dates */
      if ([[record objectForKey: @"exception dates"] count]) {
        NSMutableArray *exceptionDates = [NSMutableArray arrayWithCapacity: [[record objectForKey: @"exception dates"] count]];
        
        for (id exception in [record objectForKey: @"exception dates"])
          [exceptionDates addObject: [exception dateWithCalendarFormat: nil timeZone: nil]];
        
        [record setObject: exceptionDates forKey: @"exception dates"];
      }
      
      [fixedRecords setObject: record forKey: uuid];
    }
    
    [persistentStore setObject: fixedRecords forKey: key];
  }
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"read persistent store from NSUserDefaults: %s\n", NS2CH(persistentStore));
}
@end
