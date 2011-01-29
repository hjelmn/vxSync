/* (-*- objc -*-)
 * vxSync: LGPBSpeedFile.h
 * Copyright (C) 2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined (LGPBSPEEDFILE_H)
#define LGPBSPEEDFILE_H

#include "LGPBEntryFile.h"

@interface LGPBEntryFile (Speeds)
- (int) readSpeeds;
- (int) commitSpeeds;
- (NSArray *) speedsForContact: (int) contactIndex;
- (int) setSpeedDial: (int) speedNumber withContact: (int) contactIndex numberType: (int) numberType;
@end

#endif