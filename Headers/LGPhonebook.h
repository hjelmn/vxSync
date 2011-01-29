/* (-*- objc -*-)
 * vxSync: LGPhonebook.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.4
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */
#if !defined(LGPHONEBOOK_H)
#define LGPHONEBOOK_H

#include "VXSync.h"
#include "LGPBEntryFile.h"

@interface LGPhonebook : NSObject <LGData> {
@private
  vxPhone *phone;
  id <LGDataDelegate> delegate;
  LGPBEntryFile *phonebookData;
  NSArray *supportedEntities;
  struct lg_ice_entry iceData[3];
}

@property (retain) NSArray *supportedEntities;

@property (retain) vxPhone *phone;

@property (retain) id <LGDataDelegate> delegate;
@property (retain) LGPBEntryFile *phonebookData;

@end

#endif
