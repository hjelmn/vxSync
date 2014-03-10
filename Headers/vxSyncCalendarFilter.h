/* (-*- objc -*-)
 * vxSync: vxSyncCalendarFilter.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
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
