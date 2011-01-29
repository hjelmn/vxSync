/* (-*- objc -*-)
 * vxSync: VXSyncDataDelegate.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(VXSYNCDATADELEGATE_H)
#define VXSYNCDATADELEGATE_H
#include "VXSyncDataSource.h"

@interface VXSyncDataSource (LGDataDelegate) <LGDataDelegate>
- (void) getIdentifierForRecord: (NSMutableDictionary *) anObject compareKeys: (NSArray *) keys isNew: (BOOL *) pIsNew;
- (id) findRecordWithIdentifier: (NSString *) identifier entityName: (NSString *) entityName;

- (id) removeRecordWithIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName;
- (void) addRecord: (NSDictionary *) record withIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName;
- (void) modifyRecord: (NSDictionary *) record withIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName;
@end

#endif
