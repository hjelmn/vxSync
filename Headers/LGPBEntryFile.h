/* (-*- objc -*-)
 * vxSync: LGPBEntryFile.h
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

#if !defined(LGPBENTRYFILE_H)
#define LGPBENTRYFILE_H

#include "VXSync.h"
#include "vxPhone.h"

struct entry_data {
  unsigned char flag, primaryNumberType;
  unsigned int entryIndex, identifier;
  NSString *name;
  NSString *email[2];
  NSString *numbers[5];
  int picID, ringID, addressIndex, groupID;
  BOOL isCompany;
};

@interface LGPBEntryFile : NSObject {
  int maxGroupCount;
@protected
  unsigned char *bytes;
  unsigned short *_inUseFlag;
  NSMutableData *_internalBuffer, *_inUseData;
  
  int contactLimit, groupLimit, contactGroupLimit;

  int currentIndex;
  vxPhone *phone;
  
  int sessionLastIndex, prevSessionLastIndex;
  u_int32_t sessionLastID, prevSessionLastID;
  int nameLength, emailCount;
  int emailLength, ringIDOffset, picIDOffset, idOffset;
  int pbpEmailOffset, pbpNumberOffset, numberLength, pbpPrimaryNumberOffset;
  int numCount, addressOffset, recordLength;
  int pbpNameOffset, groupOffset, ringtoneIDOffset, pictureIDOffset;
  int addressEntryLength;
  BOOL supportsIM, supportsStreetAddress, supportsFavorites, supportsNotes;

  NSStringEncoding nameEncoding;
  NSMutableDictionary *currentContact;
  NSMutableArray *_contacts, *speeds, *groups, *favorites;
  NSMutableArray *toDelete;
  
  id <LGDataDelegate> dataDelegate;
}

@property (retain) vxPhone *phone;

@property BOOL supportsStreetAddress;
@property BOOL supportsIM;
@property BOOL supportsFavorites;
@property BOOL supportsNotes;

@property int numberLength;

@property int contactGroupLimit;

@property (retain) id <LGDataDelegate> dataDelegate;
@property (retain) NSMutableArray *groups;
@property (retain) NSMutableArray *speeds;
@property (retain) NSMutableArray *favorites;
@property (retain) NSMutableArray *toDelete;

+ (id) phonebookWithPhone: (vxPhone *) phoneIn;
- (id) initWithPhone: (vxPhone *) phoneIn;

- (int) refreshData;

- (void) setupValues;
- (BOOL) supportsIMService: (NSString *) service;

- (void) dealloc;

- (int) getIndex;
- (int) setIndex: (unsigned int) i;

- (int) prepareNewContact;

- (BOOL) entryIsValid;
- (void) clearEntry;
- (void) clearAllEntries;

- (NSString *) getEntryName;
- (void) setEntryName: (NSString *) fullName;

- (NSString *) getEntryNotes;
- (void) setEntryNotes: (NSString *) notes;

- (NSString *) getEntryRingtonePath;
- (void) setEntryRingtonePath: (NSString *) ringtonePath;

- (NSData *) getEntryPictureData;
- (void) setEntryPictureData: (NSData *) pictureData;

- (NSArray *) getEntryGroupIDs;
- (void) setEntryGroupIDs: (NSArray *) gIds;

- (NSDictionary *) getEntryAddress;
- (int) setEntryAddress: (NSDictionary *) streetAddress;

- (NSArray *) getEntryIM;
- (int) setEntryIM: (NSDictionary *) im;

/* phone numbers (up to 5) */
- (NSArray *) getEntryPhoneNumbers;
- (int) getEntryPrimaryNumberType;
- (void) setEntryPrimaryNumberType: (const unsigned char) type;
- (int) setEntryPhoneNumberOfType: (const unsigned char) type to: (NSDictionary *) numberDict;
- (BOOL) entryNumberTypeInUse: (const unsigned char) type;

/* email addresses (up to 2) */
- (NSArray *) getEntryEmails;
- (int) setEntryEmail: (NSString *) email index: (int) aIndex;
- (int) getEntryFirstFreeEmailIndex;

- (BOOL) getEntryDisplayAsCompany;
- (void) setEntryDisplayAsCompany: (BOOL) value;

- (int) commitChanges;
@end

@interface LGPBStandard2 : LGPBEntryFile {
  id dontcare;
}
@end
@interface LGPBStandardUnicode2 : LGPBStandard2 {
  id dontcare1;
}

@end
@interface LGPBExtended2 : LGPBStandard2 {
  id dontcare2;
}

@end
@interface LGPBExtended2v2 : LGPBExtended2 {
  id dontcare3;
}

@end
@interface LGPBExtended2v3 : LGPBExtended2 {
  id dontcare4;
}

@end

#include "LGPBGroupFile.h"
#include "LGPBSpeedFile.h"
#include "LGPBAddressFile.h"
#include "LGPBFavorites.h"

#endif
