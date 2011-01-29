/* (-*- objc -*-)
 * vxSync: LGPBAddressFile.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(LGPBADDRESSFILE_H)
#define LGPBADDRESSFILE_H

#include "LGPBEntryFile.h"

@interface LGPBEntryFile (StreetAddress)
- (int) getStreetAddress: (int) addressIndex storeIn: (NSMutableDictionary *) dict;
- (int) commitStreetAddresses;
@end

#endif