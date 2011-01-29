/* (-*- objc -*-)
 * vxSync: vxSyncGroupFilter.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(VXSYNCGROUPFILTER_H)
#define VXSYNCGROUPFILTER_H

#include "VXSync.h"

@interface vxSyncGroupFilter : NSObject <NSCoding, ISyncFiltering> {
  NSArray *groupNames;
  NSString *clientIdentifier;
  BOOL syncAllGroups;
  BOOL syncOnlyWithPhoneNumbers;

@private
  ISyncRecordSnapshot *snapshot;
}

@property (retain) NSArray *groupNames;
@property (retain) NSString *clientIdentifier;
@property (readwrite) BOOL syncAllGroups;
@property (readwrite) BOOL syncOnlyWithPhoneNumbers;

+ (vxSyncGroupFilter *) filter;
- (void) dealloc;

@property (retain) ISyncRecordSnapshot *snapshot;
@end

#endif
