/* (-*- objc -*-)
 * vxSync: LGPhonebook.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
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

#include "VXSync.h"

#include "LGPhonebook.h"

@interface LGPhonebook (hidden)
- (int) emailsForContact: (NSMutableDictionary *) contact storeIn: (NSMutableDictionary *) dict;
- (int) addressesForContact: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) records;
- (int) numbersForContact: (NSMutableDictionary *) owner numberFD: (int) numbers_fd storeIn: (NSMutableDictionary *) dict;
- (int) groupsForContact: (NSMutableDictionary *) contact storeIn: (NSMutableDictionary *) dict;
- (int) imsForContact: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) records;

- (void) addMembersToGroups: (NSMutableDictionary *) dict;

- (int) setRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew;

- (int) refreshData;

- (int) setNumber: (NSDictionary *) record recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact;
- (int) setEmail: (NSDictionary *) record recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact;
- (int) setAddress: (NSDictionary *) record recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact;
- (int) setIM: (NSDictionary *) imRecord recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact;
- (int) formatImage: (NSDictionary *) record formattedRecord: (NSMutableDictionary *) formattedRecord;
- (int) setRingtone: (NSDictionary *) record formattedRecord: (NSMutableDictionary *) formattedRecord;

- (int) commitICE;
@end

static NSInteger groupIDcompare (id group1, id group2, void *context) {
  return [[group1 objectForKey: VXKeyPhoneIdentifier] compare: [group2 objectForKey: VXKeyPhoneIdentifier]];
}

static NSString *numberTypes[] = {@"none", @"mobile", @"home", @"work", @"mobile", @"home fax"};

@implementation LGPhonebook

+ (id) sourceWithPhone: (vxPhone *) phoneIn {
  return [[[LGPhonebook alloc] initWithPhone: phoneIn] autorelease];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];
  if (!self)
    return nil;

  [self setPhone: phoneIn];

  switch ([phone formatForEntity: EntityContact]) {
    case LGPhonebookFormatStandard:
    case LGPhonebookFormatStandardU:
      [self setSupportedEntities: [NSArray arrayWithObjects: EntityGroup, EntityContact, EntityEmail, EntityNumber, nil]];
      break;
    case LGPhonebookFormatExtended:
      [self setSupportedEntities: [NSArray arrayWithObjects: EntityGroup, EntityContact, EntityEmail, EntityAddress, EntityNumber, nil]];
      break;
    case LGPhonebookFormatExtended2:
    case LGPhonebookFormatExtended3:
      [self setSupportedEntities: [NSArray arrayWithObjects: EntityGroup, EntityContact, EntityEmail, EntityAddress, EntityNumber, EntityIM, nil]];
      break;
    default:
      vxSync_log3(VXSYNC_LOG_ERROR, @"unknown/unsupported phonebook format: %i\n", [phone formatForEntity: EntityContact]);
      return nil;
  }

  return self;
}

- (NSString *) dataSourceIdentifier {
  return @"com.enansoft.contacts";
}

@synthesize supportedEntities, phone, delegate, phonebookData;

- (void) dealloc {
  [self setPhonebookData: nil];

  [self setPhone: nil];
  [self setDelegate: nil];

  [self setSupportedEntities: nil];
  
  [super dealloc];
}

- (void) readICE {
  NSData *_iceData = [[phone efs] get_file_data_from: VXPBICEPath errorOut: nil];
  if (![_iceData length])
    return;
  memcpy(iceData, [_iceData bytes], kMaxICE * sizeof (struct lg_ice_entry));
}

- (void) blankICEEntry: (unsigned int) aIndex {
  if (aIndex < kMaxICE) memset (&iceData[aIndex], 0, sizeof (struct lg_ice_entry));
}

#pragma mark formatting functions
- (NSDictionary *) formatGroup: (NSDictionary *) groupRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [[groupRecord mutableCopy] autorelease];

  [formattedRecord setValue: shortenString ([groupRecord objectForKey: @"name"], NSISOLatin1StringEncoding, 33) forKey: @"name"];
  [self formatImage: groupRecord formattedRecord: formattedRecord];

  return [[formattedRecord copy] autorelease];
}

- (NSDictionary *) formatNumber: (NSDictionary *) numberRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [[numberRecord mutableCopy] autorelease];
  /* format the phone number to include only the characters recognized by the phone then shorted it to fit */
  NSString *unformattedNumber = unformatNumber([numberRecord objectForKey: @"value"]);
  NSString *shortenedNumber = shortenString(unformattedNumber, NSASCIIStringEncoding, 49);
  
  /* re-format the number as we will would when reading from the phone */
  [formattedRecord setObject: formattedNumber ([shortenedNumber cStringUsingEncoding: NSASCIIStringEncoding]) forKey: @"value"];

  return [[formattedRecord copy] autorelease];
}

- (NSDictionary *) formatEmail: (NSDictionary *) emailRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [[emailRecord mutableCopy] autorelease];

  [formattedRecord setValue: shortenString([emailRecord objectForKey: @"value"], NSASCIIStringEncoding, 49) forKey: @"value"];

  return [[formattedRecord copy] autorelease];
}

- (NSDictionary *) formatContact: (NSDictionary *) contactRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [[contactRecord mutableCopy] autorelease];
  BOOL useUnicode = ([phone formatForEntity: EntityContact] == LGPhonebookFormatStandardU);
  NSString *fullName = nil;

  if ([[contactRecord objectForKey: @"display as company"] isEqualToString: @"company"] && ![contactRecord objectForKey: @"company name"])
    [formattedRecord setObject: @"person" forKey: @"display as company"];
  else if (![formattedRecord objectForKey: @"last name"] && ![formattedRecord objectForKey: @"first name"])
    [formattedRecord setObject: @"company" forKey: @"display as company"];
  
  /* chop down the contact name */
  if ([[formattedRecord objectForKey: @"display as company"] isEqualToString: @"company"])
    fullName = [contactRecord objectForKey: @"company name"];
  else if ([(NSString *)[formattedRecord objectForKey: @"last name"] length]) {
    if ([(NSString *)[formattedRecord objectForKey: @"first name"] length]) {
      fullName = [NSString stringWithFormat: @"%@ %@", [contactRecord objectForKey: @"first name"], [contactRecord objectForKey: @"last name"]];
    } else
      fullName = [NSString stringWithFormat: @" %@", [contactRecord objectForKey: @"last name"]];
  } else if ([(NSString *)[formattedRecord objectForKey: @"first name"] length])
    fullName = [NSString stringWithFormat: @"%@", [contactRecord objectForKey: @"first name"]];
  
  if (!fullName)
    fullName = @"No Name";

  fullName = shortenString (fullName, useUnicode ? NSUTF16LittleEndianStringEncoding : NSISOLatin1StringEncoding, useUnicode ? 66 : 33);
  
  if ([phonebookData supportsNotes] && [contactRecord objectForKey: @"notes"]) {
    NSString *note = shortenString ([contactRecord objectForKey: @"notes"], NSISOLatin1StringEncoding, 31);
    [formattedRecord setObject: note forKey: @"notes"];
  } else
    [formattedRecord removeObjectForKey: @"notes"];
  
  /* set a primary IM */
  if ([phonebookData supportsIM] && [[contactRecord objectForKey: @"IMs"] count] && ![[contactRecord objectForKey: @"primary IM"] count])
    [formattedRecord setObject: [NSArray arrayWithObject: [[contactRecord objectForKey: @"IMs"] objectAtIndex: 0]] forKey: @"primary IM"];
  
  /* set a primary street address */
  if ([phonebookData supportsStreetAddress] && [[contactRecord objectForKey: @"street addresses"] count] && ![[contactRecord objectForKey: @"primary street address"] count])
    [formattedRecord setObject: [NSArray arrayWithObject: [[contactRecord objectForKey: @"street addresses"] objectAtIndex: 0]] forKey: @"primary street address"];
  
  [formattedRecord removeObjectForKey: @"company name"];
  [formattedRecord setObject: @"person" forKey: @"display as company"];
  splitName (fullName, formattedRecord);
  
  [self formatImage: contactRecord formattedRecord: formattedRecord];
  
  return [[formattedRecord copy] autorelease];
}

- (NSDictionary *) formatIM: (NSDictionary *) imRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [[imRecord mutableCopy] autorelease];
  
  [formattedRecord setValue: shortenString([imRecord objectForKey: @"user"], NSASCIIStringEncoding, 43) forKey: @"user"];
  
  return [[formattedRecord copy] autorelease];
}

- (int) formatImage: (NSDictionary *) record formattedRecord: (NSMutableDictionary *) formattedRecord {
  CGImageRef pictureID, resizedPictureID;
  NSData *cachedData;
  id imagePath, imageData;
  NSSize oldSize;
  float oldAspect, phoneAspect, newWidth, newHeight, scaleFactor;
  CGColorSpaceRef colorspace;
  CGContextRef context;
  NSSize pictureidSize;

  pictureidSize = (NSSize) {[[phone valueForKeyPath: @"pictureid.width"] intValue], [[phone valueForKeyPath: @"pictureid.height"] intValue]};

  if ([record objectForKey: @"image"] || [record objectForKey: VXKeyPicturePath]) {
    imagePath = [record objectForKey: VXKeyPicturePath];
    imageData = [record objectForKey: @"image"];
    
    if (imagePath) {
      NSString *psPath = [NSHomeDirectory () stringByAppendingPathComponent: [NSString stringWithFormat: @"Library/Application Support/vxSync/PersistentStore/%@", imagePath]];
      cachedData = [NSData dataWithContentsOfFile: psPath];
      if ([cachedData isEqualTo: imageData])
      /* this path/data was read from the phone or was already formatted. nothing more needs to be done */
        return 0;
    }
    
    vxSync_log3(VXSYNC_LOG_INFO, @"creating a formatted image for record = %s\n", NS2CH(record));

    CGDataProviderRef imgDataProvider = CGDataProviderCreateWithCFData ((CFDataRef)imageData);
    pictureID = CGImageCreateWithPNGDataProvider (imgDataProvider, NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease (imgDataProvider);
    
    /* check picture size (don't change it if it is the right size) */
    NSSize pictureSize = (NSSize) {CGImageGetWidth (pictureID), CGImageGetHeight (pictureID)};
    if (pictureSize.height <= pictureidSize.height && pictureSize.width <= pictureidSize.width) {
      CGImageRelease (pictureID);
      return 0;
    }

    /* determine scale factor for image */
    oldSize = (NSSize) {CGImageGetWidth (pictureID), CGImageGetHeight (pictureID)};
    oldAspect   = (float)oldSize.width/(float)oldSize.height;
    phoneAspect = (float)pictureidSize.width/(float)pictureidSize.height;
    scaleFactor = (oldAspect > phoneAspect) ? pictureidSize.width/oldSize.width : pictureidSize.height/oldSize.height;
    
    newHeight = oldSize.height * scaleFactor;
    newWidth  = oldSize.width * scaleFactor;

    colorspace = CGImageGetColorSpace(pictureID);
    context = CGBitmapContextCreate(NULL, newWidth, newHeight,
                                    CGImageGetBitsPerComponent(pictureID),
                                    CGImageGetBytesPerRow(pictureID),
                                    colorspace,
                                    CGImageGetAlphaInfo(pictureID));

    CGColorSpaceRelease(colorspace);
    
    if (NULL == context)
      return 0;
    
    // draw image to context (resizing it)
    CGContextDrawImage(context, CGRectMake(0, 0, newWidth, newHeight), pictureID);
    // extract resulting image from context
    resizedPictureID = CGBitmapContextCreateImage (context);
    CGContextRelease(context);
    CGImageRelease (pictureID);

    NSMutableData *jpegData = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData ((CFMutableDataRef) jpegData, (CFStringRef) @"JPEG", 1, NULL);
    CGImageDestinationAddImage (destination, resizedPictureID, (CFDictionaryRef) [NSDictionary dictionaryWithObject: [NSNumber numberWithFloat: 0.8] forKey: (NSString *)kCGImageDestinationLossyCompressionQuality]);
    CGImageDestinationFinalize (destination);
    
    CGImageRelease (resizedPictureID);

    if ([jpegData length])
      [formattedRecord setObject: [[jpegData copy] autorelease] forKey: @"image"];
  }

  return 0;
}

- (NSDictionary *) formatAddress: (NSDictionary *) addressRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [[addressRecord mutableCopy] autorelease];

  [formattedRecord setValue: shortenString ([addressRecord objectForKey: @"street"], NSISOLatin1StringEncoding, 52) forKey: @"street"];
  [formattedRecord setValue: shortenString ([addressRecord objectForKey: @"postal code"], NSISOLatin1StringEncoding, 13) forKey: @"postal code"];
  [formattedRecord setValue: shortenString ([addressRecord objectForKey: @"city"], NSISOLatin1StringEncoding, 52) forKey: @"city"];
  [formattedRecord setValue: shortenString ([addressRecord objectForKey: @"state"], NSISOLatin1StringEncoding, 52) forKey: @"state"];
  [formattedRecord setValue: shortenString ([addressRecord objectForKey: @"country"], NSISOLatin1StringEncoding, 52) forKey: @"country"];

  return [[formattedRecord copy] autorelease];
}

- (NSDictionary *) formatRecord: (NSDictionary *) record identifier: (NSString *) identifier {
  NSString *entityName = [record objectForKey: RecordEntityName];

  if ([entityName isEqual: EntityGroup])
    return [self formatGroup: record identifier: identifier];
  else if ([entityName isEqual: EntityNumber])
    return [self formatNumber: record identifier: identifier];
  else if ([entityName isEqual: EntityContact])
    return [self formatContact: record identifier: identifier];
  else if ([entityName isEqual: EntityEmail])
    return [self formatEmail: record identifier: identifier];
  else if ([entityName isEqual: EntityAddress])
    return [self formatAddress: record identifier: identifier];
  else if ([entityName isEqual: EntityIM])
    return [self formatIM: record identifier: identifier];

  return nil;
}

#pragma mark reading functions
- (int) numbersForContact: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) dict {
  NSMutableDictionary *newNumber;
  NSMutableArray *uuids;
  NSArray *numbers;
  id number;

  numbers = [phonebookData getEntryPhoneNumbers];
  uuids = [NSMutableArray arrayWithCapacity: [numbers count]];
  
  for (number in numbers) {    
    newNumber = [[number mutableCopy] autorelease];
    
    [newNumber setObject: [NSArray arrayWithObject: [owner objectForKey: VXKeyIdentifier]] forKey: @"contact"];
    [delegate getIdentifierForRecord: newNumber compareKeys: [NSArray arrayWithObjects: @"contact", @"type", VXKeyType, nil]];

    if ([phonebookData getEntryPrimaryNumberType] == [[number objectForKey: VXKeyType] intValue])
      [owner setObject: [NSArray arrayWithObject: [newNumber objectForKey: VXKeyIdentifier]] forKey: @"primary phone number"];
    
    [[dict objectForKey: EntityNumber] setObject: newNumber forKey: [newNumber objectForKey: VXKeyIdentifier]];
    [uuids addObject: [newNumber objectForKey: VXKeyIdentifier]];
  }

  if ([uuids count])
    [owner setObject: uuids forKey: @"phone numbers"];

  return 0;
}

- (int) refreshData {
  LGPBEntryFile *_phonebook = nil;
  
  printf ("Reading phonebook...\n");
  
  switch ([phone formatForEntity: EntityContact]) {
  case LGPhonebookFormatStandard:
    _phonebook = [LGPBStandard2 phonebookWithPhone: phone];
    break;
  case LGPhonebookFormatStandardU:
    _phonebook = [LGPBStandardUnicode2 phonebookWithPhone: phone];
    break;
  case LGPhonebookFormatExtended:
    _phonebook = [LGPBExtended2 phonebookWithPhone: phone];
    break;
  case LGPhonebookFormatExtended2:
    _phonebook = [LGPBExtended2v2 phonebookWithPhone: phone];
    break;
  case LGPhonebookFormatExtended3:
    _phonebook = [LGPBExtended2v3 phonebookWithPhone: phone];
    break;
  }
  [_phonebook setDataDelegate: delegate];

  [self setPhonebookData: _phonebook];

  if (!phonebookData) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not load phonebook data\n");
    return -1;
  }

  [self	readICE];

  return [phonebookData refreshData];
}

- (NSDictionary *) readRecords {
  NSMutableDictionary *records;
  NSData *pictureData;
  int i, j;

  if (!phonebookData && ([self refreshData] < 0))
    return nil;

  records = [NSMutableDictionary dictionaryWithObjectsAndKeys:
             [NSMutableDictionary dictionary], EntityContact,
             [NSMutableDictionary dictionary], EntityNumber,
             [NSMutableDictionary dictionary], EntityAddress,
             [NSMutableDictionary dictionary], EntityEmail,
             [NSMutableDictionary dictionary], EntityIM,
             [NSMutableDictionary dictionary], EntityGroup, nil];
  
  for (i = 0 ; [phonebookData setIndex: i] == i ; i++) {
    if (YES == [phonebookData entryIsValid]) {
      NSMutableDictionary *newContact = [NSMutableDictionary dictionary];
      BOOL identifyWithIndex = YES; /* no name */
      
      [newContact setObject: EntityContact forKey: RecordEntityName];
      [newContact setObject: [NSNumber numberWithInteger: i] forKey: VXKeyIndex];

      if ([[phonebookData getEntryName] length] != 0) {
        /* this is a hack but it should work with all phones */
        if ([phonebookData getEntryDisplayAsCompany]) {
          [newContact setObject: [phonebookData getEntryName] forKey: @"company name"];
          [newContact setObject: @"company" forKey: @"display as company"];
        } else {
          splitName ([phonebookData getEntryName], newContact);
          [newContact setObject: @"person" forKey: @"display as company"];
        }
      }

      if ([[newContact objectForKey: @"first name"] isEqualToString: @"No"] && [[newContact objectForKey: @"last name"] isEqualToString: @"Name"]) {
        [newContact removeObjectForKey: @"first name"];
        [newContact removeObjectForKey: @"last name"];
      } else
        identifyWithIndex = NO;
      
      if (!identifyWithIndex)
        [delegate getIdentifierForRecord: newContact compareKeys: [NSArray arrayWithObjects: @"first name", @"last name", @"middle name", nil]];
      else
        [delegate getIdentifierForRecord: newContact compareKeys: [NSArray arrayWithObjects: VXKeyIndex, nil]];
        

      /* the identifier is a sufficient key but address book uses the name as the identity key. best to use what address book uses. */
/*      contactUid = [newContact objectForKey: VXKeyIdentifier]; */
      
      [self emailsForContact: newContact storeIn: records];
      [self groupsForContact: newContact storeIn: records];
      [self addressesForContact: newContact storeIn: records];
      [self imsForContact: newContact storeIn: records];
      
      if ([phonebookData getEntryNotes])
        [newContact setObject: [phonebookData getEntryNotes] forKey: @"notes"];

      pictureData  = [phonebookData getEntryPictureData];
      if (pictureData)
        [newContact setObject: pictureData forKey: @"image"];
      if ([phonebookData getEntryRingtonePath])
        [newContact setObject: [phonebookData getEntryRingtonePath] forKey: VXKeyRingtonePath];
      
      [self numbersForContact: newContact storeIn: records];
      
      for (j = 0 ; j < 3 ; j++)
        if (iceData[j].is_assigned && OSSwapLittleToHostInt32(iceData[j].entry_index) == i)
          [newContact setObject: [NSNumber numberWithUnsignedShort: j] forKey: VXKeyICEIndex];

      [[records objectForKey: EntityContact] setValue: newContact forKey: [newContact objectForKey: VXKeyIdentifier]];
    }
  }

  [self addMembersToGroups: records];
  
  return records;
}

- (void) addMembersToGroups: (NSMutableDictionary *) dict {
  NSArray *groups = [phonebookData groups];
  
  for (id group in groups) {
    NSString *groupIdentifier = [group objectForKey: VXKeyIdentifier];
    NSMutableArray *members = [NSMutableArray array];
    NSMutableDictionary *newGroup = [[group mutableCopy] autorelease];
    
    for (id aContact in [[dict objectForKey: EntityContact] allValues]) {
      NSArray *parentGroups = [aContact objectForKey: VXKeyOnPhoneGroups];

      if (parentGroups && [parentGroups indexOfObject: groupIdentifier] != NSNotFound)
        [members addObject: [aContact objectForKey: VXKeyIdentifier]];
    }

    [newGroup setObject: members forKey: @"members"];    
    [[dict objectForKey: EntityGroup] setObject: newGroup forKey: groupIdentifier];
  }
  
  vxSync_log3(VXSYNC_LOG_INFO, @"read groups = %s\n", NS2CH([dict objectForKey: EntityGroup]));
}

- (int) groupsForContact: (NSMutableDictionary *) contact storeIn: (NSMutableDictionary *) dict {
  NSArray *groupIndices = [phonebookData getEntryGroupIDs];
  NSMutableArray *parentGroups = [NSMutableArray array];
  
  for (id groupIndex in groupIndices) {
    NSString *groupIdentifier = [phonebookData getIdentifierForGroupWithID: [groupIndex unsignedIntValue]];

    if (groupIdentifier)
      [parentGroups addObject: groupIdentifier];
  }
  [contact setObject: [[parentGroups copy] autorelease] forKey: VXKeyOnPhoneGroups];

  return 0;
}

- (int) emailsForContact: (NSMutableDictionary *) contact storeIn: (NSMutableDictionary *) records {
  NSString *contactUUID = [contact objectForKey: VXKeyIdentifier];
  NSArray *emails;
  NSMutableArray *uuidArray = [NSMutableArray array];
  id email;
  
  emails = [phonebookData getEntryEmails];
  for (email in emails) {
    NSMutableDictionary *newEmail = [[email mutableCopy] autorelease];
    id previous;
    
    [newEmail setObject: [NSArray arrayWithObject: contactUUID] forKey: @"contact"];
    [newEmail setObject: EntityEmail forKey: RecordEntityName];
    
    [delegate getIdentifierForRecord: newEmail compareKeys: [NSArray arrayWithObjects: @"contact", @"value", nil]];
    previous = [delegate findRecordWithIdentifier: [newEmail objectForKey: VXKeyIdentifier] entityName: EntityEmail];
    
    if (previous) {
      [newEmail setObject: [previous objectForKey: @"type"] forKey: @"type"];
      
      if ([previous objectForKey: @"label"])
        [newEmail setObject:[previous objectForKey: @"label"] forKey: @"label"];
    } else  {
      if ([[email objectForKey: @"value"] hasSuffix: @"@mac.com"] || [[email objectForKey: @"value"] hasSuffix: @"@me.com"]) {
        [newEmail setObject: @"MobileMe" forKey: @"label"];
        [newEmail setObject: @"other" forKey: @"type"];
      } else
        [newEmail setObject: @"home" forKey: @"type"];
    }
    
    [[records objectForKey: EntityEmail] setObject: newEmail forKey: [newEmail objectForKey: VXKeyIdentifier]];
    [uuidArray addObject: [newEmail objectForKey: VXKeyIdentifier]];
  }
  
  if ([uuidArray count])
    [contact setObject: [NSArray arrayWithArray: uuidArray] forKey: @"email addresses"];
  
  return 0;
}

- (int) addressesForContact: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) records {
  NSMutableDictionary *newAddress = [[[phonebookData getEntryAddress] mutableCopy] autorelease];

  if (newAddress) {
    NSDictionary *oldRecord;

    [newAddress setObject: [NSArray arrayWithObject: [owner objectForKey: VXKeyIdentifier]] forKey: @"contact"];
    
    [delegate getIdentifierForRecord: newAddress compareKeys: [NSArray arrayWithObjects: @"contact", @"street", @"city", @"country", @"postal code", @"state", nil]];
    oldRecord = [delegate findRecordWithIdentifier: [newAddress objectForKey: VXKeyIdentifier] entityName: EntityAddress];
    
    if ([oldRecord objectForKey: @"type"])
      [newAddress setObject: [oldRecord objectForKey: @"type"] forKey: @"type"];
    if ([oldRecord objectForKey: @"label"])
      [newAddress setObject: [oldRecord objectForKey: @"label"] forKey: @"label"];
    
    [[records objectForKey: EntityAddress] setObject: newAddress forKey: [newAddress objectForKey: VXKeyIdentifier]];
    [owner setObject: [NSArray arrayWithObject: [newAddress objectForKey: VXKeyIdentifier]] forKey: @"street addresses"];
    [owner setObject: [NSArray arrayWithObject: [newAddress objectForKey: VXKeyIdentifier]] forKey: @"primary street address"];
  }

  return 0;
}

- (int) imsForContact: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) records {
  NSMutableDictionary *newIM = [[[phonebookData getEntryIM] mutableCopy] autorelease];
  
  if (newIM) {
    NSDictionary *oldRecord;
    
    [newIM setObject: [NSArray arrayWithObject: [owner objectForKey: VXKeyIdentifier]] forKey: @"contact"];
    
    [delegate getIdentifierForRecord: newIM compareKeys: [NSArray arrayWithObjects: @"contact", @"service", @"user", nil]];
    oldRecord = [delegate findRecordWithIdentifier: [newIM objectForKey: VXKeyIdentifier] entityName: EntityIM];
    if ([oldRecord objectForKey: @"type"])
      [newIM setObject: [oldRecord objectForKey: @"type"] forKey: @"type"];
    if ([oldRecord objectForKey: @"label"])
      [newIM setObject: [oldRecord objectForKey: @"label"] forKey: @"label"];
    
    [[records objectForKey: EntityIM] setObject: newIM forKey: [newIM objectForKey: VXKeyIdentifier]];
    [owner setObject: [NSArray arrayWithObject: [newIM objectForKey: VXKeyIdentifier]] forKey: @"IMs"];
    [owner setObject: [NSArray arrayWithObject: [newIM objectForKey: VXKeyIdentifier]] forKey: @"primary IM"];
  }
  
  return 0;
}

#pragma mark write functions
/* XXX -- TODO -- Update this code because the oldrecord way does not work anymore */
- (int) setContact: (NSDictionary *) contactRecord formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew {
  int ret, i, numberType;
  NSMutableDictionary *formattedRecord;
  NSString *fullName;
  id group;
  NSDictionary *formattedRelation;

  BOOL numberTypeInUse[6];

  if (isNew)
    ret = [phonebookData prepareNewContact];
  else
    ret = [phonebookData setIndex: [[contactRecord objectForKey: VXKeyIndex] integerValue]];
  if (ret < 0)
    return ret;

  formattedRecord = [[contactRecord mutableCopy] autorelease];

  [formattedRecord setObject: [NSNumber numberWithInt: [phonebookData getIndex]] forKey: VXKeyIndex];

  if ([[contactRecord objectForKey: @"display as company"] isEqualToString: @"company"]) {
    [phonebookData setEntryName: [contactRecord objectForKey: @"company name"]];
    [phonebookData setEntryDisplayAsCompany: YES];
  } else {
    if ([contactRecord objectForKey: @"last name"]) {
      if ([[phone getOption: @"contacts.formatLastFirst"] boolValue])
        fullName = [NSString stringWithFormat: @"%@, %@", [contactRecord objectForKey: @"last name"], [contactRecord objectForKey: @"first name"]];
      else
        fullName = [NSString stringWithFormat: @"%@ %@", [contactRecord objectForKey: @"first name"], [contactRecord objectForKey: @"last name"]];
    } else
      fullName = [NSString stringWithFormat: @"%@", [contactRecord objectForKey: @"first name"]];
    [phonebookData setEntryName: fullName];
    [phonebookData setEntryDisplayAsCompany: NO];
  }
  
  int maxGroups = [phonebookData contactGroupLimit];
  NSArray *parentGroups = [contactRecord objectForKey: @"parent groups"];
  NSMutableArray *syncedParentGroups = [NSMutableArray array];
  NSMutableArray *groupIDs = [NSMutableArray array];
  for (i = 0 ; i < [parentGroups count] && i < maxGroups ; i++) {
    group = [delegate findRecordWithIdentifier: [parentGroups objectAtIndex: i] entityName: EntityGroup];
    
    if ([[group objectForKey: VXKeyOnPhone] boolValue]) {
      [syncedParentGroups addObject: [parentGroups objectAtIndex: i]];
      [groupIDs addObject: [group objectForKey: VXKeyPhoneIdentifier]];
    }
  }
  [formattedRecord setObject: syncedParentGroups forKey: VXKeyOnPhoneGroups];
  [phonebookData setEntryGroupIDs: groupIDs];

  /* setup email addresses */
  /* XXX -- TODO -- Clear old email addresses */
  for (id emailIdentifier in [contactRecord objectForKey: @"email addresses"]) {
    NSDictionary *emailRecord = [delegate findRecordWithIdentifier: emailIdentifier entityName: EntityEmail];

    ret = [self setEmail: emailRecord recordIdentifier: emailIdentifier formattedRecordOut: &formattedRelation parentContact: contactRecord];
    if (0 == ret) {
      if (formattedRelation)
        [delegate modifyRecord: formattedRelation withIdentifier: emailIdentifier withEntityName: EntityEmail];
    }
  }
  /* done with email addresses */

  /* set up phone numbers */
  for (i = 0 ; i < 5 ; i++)
    numberTypeInUse[i+1] = NO;

  for (id numberIdentifier in [contactRecord objectForKey: @"phone numbers"]) {
    NSMutableDictionary *numberRecord = [[[delegate findRecordWithIdentifier: numberIdentifier entityName: EntityNumber] mutableCopy] autorelease];
    if ([numberRecord objectForKey: VXKeyType]) {
      numberType = [[numberRecord objectForKey: VXKeyType] intValue];
      if (numberType > 0 && numberType < 6)
        numberTypeInUse[numberType] = YES;
    }
  }

  /* set phone numbers */
  for (id numberIdentifier in [contactRecord objectForKey: @"phone numbers"]) {
    NSMutableDictionary *numberRecord = [[[delegate findRecordWithIdentifier: numberIdentifier entityName: EntityNumber] mutableCopy] autorelease];
    
    if (![numberRecord objectForKey: VXKeyType]) {
      NSString *type = [numberRecord objectForKey: @"type"];
      
      for (numberType = 1 ; numberType < 6 ; numberType++)
        if ([type isEqual: numberTypes[numberType]] && !numberTypeInUse[numberType])
          /* we have room for this number */
          break;
    } else
      numberType  = [[numberRecord objectForKey: VXKeyType] intValue];
    
    if (numberType > 0 && numberType < 6) {
      numberTypeInUse[numberType] = YES;
      formattedRelation = nil;
      [numberRecord setValue: [NSNumber numberWithInt: numberType] forKey: VXKeyType];
      
      [self setNumber: numberRecord recordIdentifier: numberIdentifier formattedRecordOut: &formattedRelation parentContact: contactRecord];      
      [delegate modifyRecord: formattedRelation withIdentifier: numberIdentifier withEntityName: EntityNumber];
      if ([[contactRecord objectForKey: @"primary phone number"] indexOfObject: numberIdentifier] != NSNotFound)
        [phonebookData setEntryPrimaryNumberType: numberType];
    }
    /* else reject number */
  }
  
  /* clear deleted number types */
  for (numberType = 1 ; numberType < 6 ; numberType++) {
    if (numberTypeInUse[numberType] == NO && [phonebookData entryNumberTypeInUse: numberType])
      [phonebookData setEntryPhoneNumberOfType: numberType to: nil];
  }
  
  /* done with phone numbers */

  id addressIdentifier = nil;
  
  if ([[contactRecord objectForKey: @"primary street address"] count])
    addressIdentifier = [[contactRecord objectForKey: @"primary street address"] objectAtIndex: 0];
  else if ([[contactRecord objectForKey: @"street addresses"] count])
    addressIdentifier = [[contactRecord objectForKey: @"street addresses"] objectAtIndex: 0];

  id addressRecord = [delegate findRecordWithIdentifier: addressIdentifier entityName: EntityAddress];

  ret = [self setAddress: addressRecord recordIdentifier: addressIdentifier formattedRecordOut: &formattedRelation parentContact: contactRecord];
  if (addressRecord && (0 == ret))
    [delegate modifyRecord: formattedRelation withIdentifier: addressIdentifier withEntityName: EntityAddress];
  
  id imIdentifier, imRecord = nil;
  
  if ([[contactRecord objectForKey: @"primary IM"] count]) {
    imIdentifier = [[contactRecord objectForKey: @"primary IM"] objectAtIndex: 0];
    imRecord = [delegate findRecordWithIdentifier: imIdentifier entityName: EntityIM];

    if (![phonebookData supportsIMService: [imRecord objectForKey: @"service"]])
      imIdentifier = imRecord = nil;
  }
  
  if (!imRecord) {
    for (imIdentifier in [contactRecord objectForKey: @"IMs"]) {
      imRecord = [delegate findRecordWithIdentifier: imIdentifier entityName: EntityIM];

      if ([phonebookData supportsIMService: [imRecord objectForKey: @"service"]])
        break;
        
      imRecord = nil;
    }
  }  

  if ([contactRecord objectForKey: @"notes"] && [phonebookData supportsNotes])
    [phonebookData setEntryNotes: [contactRecord objectForKey: @"notes"]];
  
  ret = [self setIM: imRecord recordIdentifier: imIdentifier formattedRecordOut: &formattedRelation parentContact: contactRecord];
  if (imRecord && (0 == ret))
    [delegate modifyRecord: formattedRelation withIdentifier: imIdentifier withEntityName: EntityIM];
  
  [phonebookData setEntryPictureData: [contactRecord objectForKey: @"image"]];
  [phonebookData setEntryRingtonePath: [contactRecord objectForKey: VXKeyRingtonePath]];

  *recordOut = formattedRecord;

  return 0;
}

- (int) deleteRecord: (NSDictionary *) record {
  NSDictionary *contactRecord;

  vxSync_log3(VXSYNC_LOG_INFO, @"deleting record: %s\n", NS2CH(record));
  
  if (!phonebookData && ([self refreshData] < 0))
    return -1;

  /* record is not on phone */
  if (![[record objectForKey: VXKeyOnPhone] boolValue])
    return 0;
  
  if ([[record objectForKey: RecordEntityName] isEqualToString: EntityContact]) {
    [phonebookData setIndex: [[record objectForKey: VXKeyIndex] integerValue]];
    if ([record objectForKey: VXKeyICEIndex])
      [self blankICEEntry: [[record objectForKey: VXKeyICEIndex] unsignedIntValue]];
    [phonebookData clearEntry];
  } else if ([[record objectForKey: RecordEntityName] isEqualToString: EntityGroup]) {
    return [phonebookData deleteGroup: record];
  } else {
    contactRecord = [delegate findRecordWithIdentifier: [[record objectForKey: @"contact"] objectAtIndex: 0] entityName: EntityContact];
  
    /* contact was already deleted */
    if (!contactRecord)
      return 0;
    
    [phonebookData setIndex: [[contactRecord objectForKey: VXKeyIndex] intValue]];

    vxSync_log3(VXSYNC_LOG_INFO, @"contact record: %s\n", NS2CH(contactRecord));

    if ([[record objectForKey: RecordEntityName] isEqualToString: EntityNumber]) {
      if ([record objectForKey: VXKeyType])
        [phonebookData setEntryPhoneNumberOfType: [[record objectForKey: VXKeyType] intValue] to: nil];
    } else if ([[record objectForKey: RecordEntityName] isEqualToString: EntityAddress])
      [phonebookData setEntryAddress: nil];
    else if ([[record objectForKey: RecordEntityName] isEqualToString: EntityEmail])
      [phonebookData setEntryEmail: nil index: [[record objectForKey: VXKeyParentIndex] intValue]];
  }

  /* Address, Email, and Name deletions are handled when the Contact is updated */
  return 0;
}

- (BOOL) deleteAllRecordsForEntityName: (NSString *) entityName {
  return NO;
}

- (BOOL) deleteAllRecords {
  [self refreshData];

  [phonebookData clearAllEntries];
  [phonebookData clearAllGroups];
  
  memset (iceData, 0, kMaxICE * sizeof (struct lg_ice_entry));
  
  return YES;
}

- (int) modifyRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  if ([[record objectForKey: RecordEntityName] isEqualToString: EntityGroup])
    return [phonebookData modifyGroup: record recordOut: recordOut identifier: identifier isNew: NO];
  else
    return [self setRecord: record formattedRecordOut: recordOut identifier: identifier isNew: NO];
}

- (int) addRecord:  (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  return [self setRecord: record formattedRecordOut: recordOut identifier: identifier isNew: YES];
}

- (int) setRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew {
  NSString *entityName = [record objectForKey: RecordEntityName];
  id contact;

  if (!phonebookData) {
    [self refreshData];
    if (!phonebookData)
      return -1;
  }

  if ([entityName isEqualToString: EntityContact])
    return [self setContact: record formattedRecordOut: recordOut identifier: identifier isNew: isNew];
  else if ([entityName isEqualToString: EntityGroup])
    return [phonebookData addGroup: record recordOut: recordOut identifier: identifier];

  contact = [delegate findRecordWithIdentifier: [[record objectForKey: @"contact"] objectAtIndex: 0] entityName: EntityContact];
  
  if (contact) {
    [phonebookData setIndex: [[contact objectForKey: VXKeyIndex] integerValue]];

    if ([entityName isEqualToString: EntityAddress])
      return [self setAddress: record recordIdentifier: identifier formattedRecordOut: recordOut parentContact: contact];

    if ([entityName isEqualToString: EntityEmail])
      return [self setEmail: record recordIdentifier: identifier formattedRecordOut: recordOut parentContact: contact];

    if ([entityName isEqualToString: EntityNumber])
      return [self setNumber: record recordIdentifier: identifier formattedRecordOut: recordOut parentContact: contact];
    
    if ([entityName isEqualToString: EntityIM])
      return [self setIM: record recordIdentifier: identifier formattedRecordOut: recordOut parentContact: contact];
  }

  /* unsupported entity type */
  return 0;
}

- (int) setEmail: (NSDictionary *) emailRecord recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact {
  NSMutableDictionary *formattedRecord = [[emailRecord mutableCopy] autorelease];
  int parentIndex;

  if (![emailRecord objectForKey: VXKeyParentIndex]) {
    parentIndex = [phonebookData getEntryFirstFreeEmailIndex];
    if (-1 == parentIndex) {
      vxSync_log3(VXSYNC_LOG_INFO, @"no free email indices. this probaly should not happen!\n");
      return -2;
    }
  } else
    parentIndex = [[emailRecord objectForKey: VXKeyParentIndex] intValue];

  [formattedRecord setObject: [NSNumber numberWithInt: parentIndex] forKey: VXKeyParentIndex];
  [formattedRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];
  *recordOut = formattedRecord;
  
  [phonebookData setEntryEmail: [emailRecord objectForKey: @"value"] index: parentIndex];

  return 0;
}

- (int) setNumber: (NSDictionary *) numberRecord recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact {
  u_int8_t numberType;
  NSMutableDictionary *formattedRecord;

  if (![numberRecord objectForKey: VXKeyType]) {
    NSString *type = [numberRecord objectForKey: @"type"];

    for (numberType = 1 ; numberType < 6 ; numberType++)
      if (![phonebookData entryNumberTypeInUse: numberType] && [type isEqualToString: numberTypes[numberType]])
        break;
  } else
    numberType  = [[numberRecord objectForKey: VXKeyType] intValue];
  
  if (numberType > 5)
    /* no space for this number */
    return -2;
  
  /* save vxSync hints (these will be removed by the data source for syncing with isync) */
  formattedRecord = [[numberRecord mutableCopy] autorelease];

  [formattedRecord setObject: [NSNumber numberWithInt: numberType] forKey: VXKeyType];
  [formattedRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];
  
  [phonebookData setEntryPhoneNumberOfType: numberType to: numberRecord];
  
  *recordOut = formattedRecord;

  return 0;
}

- (int) setAddress: (NSDictionary *) addressRecord recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact {
  if (addressRecord) {
    if ([phonebookData supportsStreetAddress] == NO || [[contact objectForKey: @"street addresses"] indexOfObject: identifier] == NSNotFound)
    /* not supported or not first address */
      return -2;
    
    NSMutableDictionary *formattedRecord = [[addressRecord mutableCopy] autorelease];
    [formattedRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];
    *recordOut = formattedRecord;
  }

  [phonebookData setEntryAddress: addressRecord];

  return 0;
}

- (int) setIM: (NSDictionary *) imRecord recordIdentifier: (NSString *) identifier formattedRecordOut: (NSDictionary **) recordOut parentContact: (NSDictionary *) contact {
  if (imRecord) {
    if ([phonebookData supportsIM] == NO || [[contact objectForKey: @"IMs"] indexOfObject: identifier] == NSNotFound)
      /* not supported */
      return -2;

    NSMutableDictionary *formattedRecord = [[imRecord mutableCopy] autorelease];
    [formattedRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];
    *recordOut = formattedRecord;
  }
  
  [phonebookData setEntryIM: imRecord];
  
  return 0;
}

- (int) commitICE {
  int ret = [[phone efs] write_file_data: [NSData dataWithBytes: iceData length: kMaxICE * sizeof (struct lg_ice_entry)] to: VXPBICEPath];
  return (ret == kMaxICE * sizeof (struct lg_ice_entry)) ? 0 : -1;
}

#pragma mark commit
- (int) commitChanges {
  [self commitICE];
  
  /* commit phonebook changes */
  return [phonebookData commitChanges];
}

@end
