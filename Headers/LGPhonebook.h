/* (-*- objc -*-)
 * vxSync: LGPhonebook.h
 * Copyright (C) 2009-2011 Nathan Hjelm
 * v0.8.5
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
