/* (-*- objc -*-)
 * vxSync: VXSyncDataDelegate.h
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
