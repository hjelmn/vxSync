/* (-*- objc -*-)
 * vxSync: LGPBGroupFile.h
 * Copyright (C) 2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
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