/* (-*- objc -*-)
 * vxSync: vxSyncGroupFilter.h
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
