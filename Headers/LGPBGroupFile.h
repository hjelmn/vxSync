/* (-*- objc -*-)
 * vxSync: LGPBGroupFile.h
 * Copyright (C) 2010 Nathan Hjelm
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

#if !defined(LGPBGROUPFILE_H)
#define LGPBGROUPFILE_H

#include <Cocoa/Cocoa.h>
#include "LGPBEntryFile.h"

@interface LGPBEntryFile (Groups)
- (int) readGroups;
- (int) commitGroups;

- (NSString *) getIdentifierForGroupWithID: (short) groupID;
- (int) addGroup: (NSDictionary *) record recordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier;
- (int) modifyGroup: (NSDictionary *) record recordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew;   
- (int) deleteGroup: (NSDictionary *) record;

- (void) clearAllGroups;
        
@end

#endif