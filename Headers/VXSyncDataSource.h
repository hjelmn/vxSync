/* (-*- objc -*-)
 * vxSync: VXSyncDataSource.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.4
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(VXSYNCDATSOURCE_H)
#define VXSYNCDATSOURCE_H

#include "VXSync.h"

/* data sources */
#include "LGMemos.h"
#include "LGCalendar.h"
#include "LGPhonebook.h"

@interface VXSyncDataSource : NSObject <ISyncSessionDriverDataSource> {
  ISyncSessionDriver *sessionDriver;
@private
  vxPhone *phone;
  NSBundle *bundle;
  NSMutableDictionary *persistentStore, *syncModes;
  NSMutableArray *dataSources, *supportedEntities;
  NSDictionary *phoneChanges;
  ISyncRecordSnapshot *snapshot;
  ISyncClient *client;
}

@property (retain) ISyncSessionDriver *sessionDriver;
@property (retain) vxPhone *phone;
@property (retain) NSBundle *bundle;
@property (retain) NSDictionary *phoneChanges;
@property (retain) ISyncRecordSnapshot *snapshot;
@property (retain) NSMutableArray *dataSources;
@property (retain) NSMutableDictionary *persistentStore;
@property (retain) NSMutableArray *supportedEntities;
@property (retain) NSMutableDictionary *syncModes;
@property (retain) ISyncClient *client;

+ (id) dataSourceWithPhone: (vxPhone *) phoneIn;
- (id) initWithPhone: (vxPhone *) phoneIn;
- (void) dealloc;

/* (R) Returns the client’s unique identifier specified when registering the client. */
- (NSString *) clientIdentifier;

/* (R) Returns an NSURL object representing the path to the client description property list. */
- (NSURL *) clientDescriptionURL;
/* same thing as above but returns a UNIX file path */
- (NSString *) clientDescriptionPath;

/* (R) Returns an array containing NSURL objects representing the path to schemas this client uses. */
- (NSArray *) schemaBundleURLs;

/* (O) Returns an array of NSString objects representing the names of entities this client wants to sync. */
- (NSArray *) entityNamesToSync;
/* (O) Returns an array of NSString objects representing the names of entities this client wants to pull. */
- (NSArray *) entityNamesToPull;

/* (R) Returns records for the given entity name that should be pushed to the sync engine during a slow sync. */
- (NSDictionary *) recordsForEntityName: (NSString *) entityName moreComing: (BOOL *) moreComing error: (NSError **) outError;
/* (R for fast sync) Returns changed records for the given entity name that should be pushed to the sync engine during a fast sync. */
- (NSArray *) changesForEntityName: (NSString *) entity moreComing: (BOOL *) moreComing error: (NSError **) outError;
/* (R) Applies the given changes to a client's record during the pulling phase of a sync session. */
- (ISyncSessionDriverChangeResult) applyChange: (ISyncChange *) change forEntityName:(NSString *)entityName
		      remappedRecordIdentifier: (NSString **) outRecordIdentifier formattedRecord: (NSDictionary **) outRecord
					 error: (NSError **) outError;

/* (R) Deletes all records for the specified entity. */
- (BOOL)deleteAllRecordsForEntityName: (NSString *) entityName error: (NSError **) outError;
/* (R) Returns the client's preferred sync mode for the session. */
- (ISyncSessionDriverMode) preferredSyncModeForEntityName: (NSString *) entity;
@end
  
#endif
