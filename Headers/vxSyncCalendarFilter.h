/* (-*- objc -*-)
 * vxSync: vxSyncCalendarFilter.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(VXSYNCCALENDARFILTER_H)
#define VXSYNCCALENDARFILTER_H

#include "VXSync.h"

@interface vxSyncCalendarFilter : NSObject <NSCoding, ISyncFiltering> {
  NSArray *calendarTitles;
  NSString *clientIdentifier;
@private
  ISyncRecordSnapshot *snapshot;
}

@property (retain,readwrite) NSArray *calendarTitles;
@property (retain) NSString *clientIdentifier;
@property (retain) ISyncRecordSnapshot *snapshot;

+ (vxSyncCalendarFilter *) filter;
- (void) dealloc;

@end

#endif
