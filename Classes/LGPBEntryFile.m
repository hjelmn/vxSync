/* (-*- objc -*-)
 * vxSync: LGPBEntryFile.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.4
 *
 * Changes:
 *  - 0.6.1 - Manage picture IDs better.
 *  - 0.6.0 - Group picture IDs
 *  - 0.3.1 - Move LGException class into a seperate file. Bug fixes and code cleanup
 *  - 0.3.0 - Cleaner code. Support for commitChanges. Better support for all day events. Multiple calendars support.
 *  - 0.2.3 - Bug fixes
 *  - 0.2.0 - Initial release
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

#include "LGPBEntryFile.h"

static NSString *numberTypes[] = {@"none", @"mobile", @"home", @"work", @"mobile", @"home fax"};

@interface LGPBEntryFile (hidden)
- (void) entrySetFileDirty;
- (void) entrySetDirty;

- (void) setValue: (id) value forKey: (NSString *) key fileChange: (BOOL) fileChange;
- (int) readRecordID;

- (void) addFileData: (NSString *) path storeTo: (NSMutableDictionary *) contact withKey: (NSString *) key;
- (void) writeFileData: (NSString *) path withData: (NSData *) fileData overWrite: (BOOL) overWrite;

- (void) readSessionData;
- (void) saveSessionData;

- (int) protocolReadEntry: (int) entryIndex storeIn: (NSMutableDictionary *) newContact;
- (int) protocolCommitEntry: (int) entryIndex;
- (int) protocolDeleteEntry: (int) entryIndex;

- (int) readID: (NSString *) fileName storeIn: (NSMutableDictionary *) dict dataKey: (NSString *) dataKey pathKey: (NSString *) pathKey entryIndex: (int) entryIndex;
- (int) writeID: (NSString *) fileName path: (NSString *) path fileData: (NSData *) data entryIndex: (int) entryIndex;
- (int) writePictureID: (int) entryIndex;
- (int) writeRingerID: (int) entryIndex;

- (void) deallocEntry;
@end

@implementation LGPBEntryFile
+ (id) phonebookWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBEntryFile alloc] initWithPhone: phoneIn] autorelease];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];

  if (nil == phoneIn) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"EFS input is nil\n");
    return nil;
  }

  [self setPhone: phoneIn];
  
  contactLimit = [phone limitForEntity: EntityContact];
  groupLimit   = [phone limitForEntity: EntityGroup];
  
  /* set up internal values based on file format */
  [self setupValues];
  
  return self;
}

- (int) refreshData {
  int i, j, fd, newSessionLastIndex = 0;
  
  [self setToDelete: [NSMutableArray array]];
  _contacts       = [[NSMutableArray arrayWithCapacity: contactLimit] retain];
  _inUseData      = [[NSMutableData dataWithLength: contactLimit * 2] retain];
  _internalBuffer = [[NSMutableData dataWithLength: 8192] retain];
  
  for (i = 0 ; i < contactLimit ; i++)
    [_contacts addObject: [NSNull null]];
  
  /*
   Breakdown of in use flags:
   0x0001 -- Contact in use
   0x0002 -- Address in use
   0x0010 -- Street address is dirty
   0x0020 -- Delete contact
   0x0040 -- pbentry.dat data dirty (requires reboot)
   0x0080 -- Phonebook data is dirty (no reboot required if 0x40 not set)
   */
  _inUseFlag = [_inUseData mutableBytes];
  bytes      = [_internalBuffer mutableBytes];
  if (NULL == bytes || NULL == _inUseFlag || nil == _contacts) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not allocate memory for internal structures!\n");
    return -1;
  }

  [self readRecordID];
  [self readSessionData];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"prevSessionLastIndex = %d, prevSessionLastID = %d, sessionLastID = %d\n", prevSessionLastIndex, prevSessionLastID, sessionLastID);
  
  sessionLastIndex = contactLimit - 1;
  
  /* this is not the most optimal solution but it is simple and much faster than the dumb solution */
  if (prevSessionLastIndex > 0 && sessionLastID >= prevSessionLastID) 
    sessionLastIndex = prevSessionLastIndex + (sessionLastID - prevSessionLastID) + 3;
  
  if (sessionLastIndex >= contactLimit)
    sessionLastIndex = contactLimit - 1;

//  [self readFavorites];

  [self readGroups];
  [self readSpeeds];

  if ([[phone efs] stat: VXPBEntryPath to: NULL]) {
    vxSync_log3(VXSYNC_LOG_INFO, @"phonebook data file not found. continuing with data from pb protocol");
  } else {
    fd = [[phone efs] open: VXPBEntryPath withFlags: O_RDONLY];
    if (-1 == fd)
      return -1;

    vxSync_log3(VXSYNC_LOG_INFO, @"data file opened for reading. Will read phonebook up to index: %i\n", sessionLastIndex);
  }

  for (i = 0 ; i <= sessionLastIndex ; i ++) {
    [[phone efs] read: fd to: bytes count: recordLength];
    /* TODO -- update to work with phones that don't have the standard pim data */
    if (OSReadLittleInt32 (bytes, idOffset) != (UInt32)-1) {
      NSMutableDictionary *newContact = [NSMutableDictionary dictionary];
      UInt16 ringtoneIndex, pictureIndex;

      _inUseFlag[i] |= 0x01;
      vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: recordLength], @"file data for contact %i:\n", i);

      [newContact setObject: [NSNumber numberWithBool: bytes[recordLength - 7] == 0x01] forKey: @"display as company"];

      NSMutableArray *_groups = [NSMutableArray arrayWithCapacity: contactGroupLimit];
      for (j = 0 ; j < contactGroupLimit ; j++) {
        unsigned int groupID = OSReadLittleInt16 (bytes, groupOffset + 2 * j);
        
        if (groupID)
          [_groups addObject: [NSNumber numberWithUnsignedInt: groupID]];
      }
      [newContact setObject: _groups forKey: @"group ids"];

      if (addressOffset > -1)
        /* read street address from the pbaddress.dat file */
        [self getStreetAddress: OSReadLittleInt16 (bytes, addressOffset) storeIn: newContact];

      ringtoneIndex = OSReadLittleInt16 (bytes, ringtoneIDOffset);
      pictureIndex  = OSReadLittleInt16 (bytes, pictureIDOffset);
      
      if (pictureIndex != 0xffff && pictureIndex >= 0x64)
        [self readID: VXPBPicureIDPath storeIn: newContact dataKey: @"image" pathKey: VXKeyPicturePath entryIndex: i];
      
      if (ringtoneIndex != 0xffff && ringtoneIndex >= 0x64)
        [self readID: VXPBRingerIDPath storeIn: newContact dataKey: @"ringtone data" pathKey: VXKeyRingtonePath entryIndex: i];

      [newContact setObject: [NSNumber numberWithUnsignedShort: ringtoneIndex] forKey: VXKeyRingtoneIndex];
      [newContact setObject: [NSNumber numberWithUnsignedShort: ringtoneIndex] forKey: VXKeyPictureIndex];

      [self protocolReadEntry: i storeIn: newContact];
      
      [_contacts replaceObjectAtIndex: i withObject: newContact];
      
      vxSync_log3(VXSYNC_LOG_INFO, @"contact at index %i (flag = %08x\n) : %s\n", i, _inUseFlag[i], NS2CH(newContact));
      
      newSessionLastIndex = i + 1;
    }
  }
  
//  [self mapFavorites];
  
  [[phone efs] close: fd];

  vxSync_log3(VXSYNC_LOG_DEBUG, @"contacts: %s\n", NS2CH(_contacts));
  
  /* save session variables */
  sessionLastIndex = newSessionLastIndex;
  [self saveSessionData];

  if ([self setIndex: 0] < -1)
    return -1;

  vxSync_log3(VXSYNC_LOG_INFO, @"loaded %i contacts from %s\n", newSessionLastIndex, NS2CH(VXPBEntryPath));

  return 0;
}

- (void) dealloc {
  vxSync_log3(VXSYNC_LOG_INFO, @"dealloc called on phonebook data\n");
  
  [self setPhone: nil];
  [_contacts release];
  [_inUseData release];
  [_internalBuffer release];
  [self setGroups: nil];
  [self setDataDelegate: nil];
  [self setSpeeds: nil];
  [self setFavorites: nil];
  [self setToDelete: nil];
  
  [super dealloc];
}

- (int) writeID: (NSString *) fileName path: (NSString *) path fileData: (NSData *) data entryIndex: (int) entryIndex {
  int fd = [[phone efs] open: fileName withFlags: O_RDWR];
  unsigned char buf2[255];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"writing id to index %d and path %s with path: %s and data: %s\n", entryIndex, NS2CH(fileName), NS2CH(path), NS2CH(data));

  [[phone efs] lseek: fd toOffset: entryIndex * 255 whence: SEEK_SET];
  
  memset (buf2, 0, 255);
  [path getCString: (char *)buf2 maxLength: 255 encoding: NSASCIIStringEncoding];

  [toDelete filterUsingPredicate: [NSPredicate predicateWithFormat: @"!(SELF == %@)", path]];
  
  [[phone efs] write: fd from: buf2 count: 255];
  [self writeFileData: path withData: data overWrite: NO];
  [[phone efs] close: fd];
  
  return 0;
}

- (int) readID: (NSString *) fileName storeIn: (NSMutableDictionary *) dict dataKey: (NSString *) dataKey pathKey: (NSString *) pathKey entryIndex: (int) entryIndex {
  int fd = [[phone efs] open: fileName withFlags: O_RDONLY];
  unsigned char buf2[255];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"reading id from %s and storing the path into key: %s data into key: %s, into %s\n", NS2CH(fileName), NS2CH(pathKey), NS2CH(dataKey), NS2CH(dict));
  
  if (fd < 0)
    return -1;
  
  [[phone efs] lseek: fd toOffset: entryIndex * 255 whence: SEEK_SET];

  memset (buf2, 0, 255);
  [[phone efs] read: fd to: buf2 count: 255];

  if (buf2[0] != 0xff && strlen ((char *)buf2)) {
    if (pathKey)
      [dict setObject: [NSString stringWithUTF8String: (char *)buf2] forKey: pathKey];
    if (dataKey)
      [self addFileData: [NSString stringWithUTF8String: (char *)buf2] storeTo: dict withKey: dataKey];
  }

  [[phone efs] close: fd];
  
  return 0;
}

- (int) writePictureID: (int) entryIndex {
  NSDictionary *contact = [_contacts objectAtIndex: entryIndex];
  return [self writeID: VXPBPicureIDPath path: [contact objectForKey: VXKeyPicturePath] fileData: [contact objectForKey: @"image"] entryIndex: entryIndex];
}

- (int) writeRingerID: (int) entryIndex {
  NSDictionary *contact = [_contacts objectAtIndex: entryIndex];
  return [self writeID: VXPBRingerIDPath path: [contact objectForKey: VXKeyRingtonePath] fileData: [contact objectForKey: @"sound"] entryIndex: entryIndex];
}

- (int) protocolReadEntry: (int) entryIndex storeIn: (NSMutableDictionary *) newContact {
  int j;

  memset (bytes, 0, 1024);
  bytes[0] = 0xf1;
  bytes[1] = 0x29;
  OSWriteLittleInt16 (bytes, 2, entryIndex);
  
  int ret = [[phone efs] send_recv_message: bytes sendLength: 4 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: ret], @"phonebook data for contact %i:\n", entryIndex);
  
  [newContact setObject: stringFromBuffer(bytes + pbpNameOffset, nameLength, nameEncoding) forKey: @"name"];
  NSMutableArray *emailAddresses = [NSMutableArray arrayWithCapacity: emailCount];
  for (j = 0 ; j < emailCount ; j++) {
    NSString *emailAddress = stringFromBuffer(bytes + pbpEmailOffset + j * emailLength, emailLength, NSISOLatin1StringEncoding);
    if ([emailAddress length])
      [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: emailAddress, @"value", [NSNumber numberWithInt: j], VXKeyParentIndex, nil]];
    else 
      [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: j], VXKeyParentIndex, nil]];
  }
  [newContact setObject: emailAddresses forKey: @"email addresses"];
  
  NSArray *contactSpeeds = [self speedsForContact: entryIndex];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"speeds for contact: %s\n", NS2CH(contactSpeeds));
  
  NSMutableArray *phoneNumbers = [NSMutableArray arrayWithCapacity: numCount];
  for (j = 0 ; j < numCount ; j++) {
    NSString *phoneNumber = formattedNumber ((char *)(bytes + pbpNumberOffset + j * numberLength));
    if ([phoneNumber length]) {
      NSMutableArray *_speeds = [NSMutableArray array];
      for (id speed in contactSpeeds) {
        if ([[speed objectForKey: VXKeyType] intValue] == (j + 1))
          [_speeds addObject: [speed objectForKey: VXKeyIndex]];
      }
      
      NSMutableDictionary *newNumber = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                        EntityNumber,                            ISyncRecordEntityNameKey,
                                        phoneNumber,                             @"value",
                                        [[numberTypes[j + 1] copy] autorelease], @"type",
                                        [NSNumber numberWithInt: j + 1],         VXKeyType,
                                        nil];
      if ([_speeds count])
        [newNumber setObject: _speeds forKey: VXKeySpeedDial];
      [phoneNumbers addObject: newNumber];
    } else
      [phoneNumbers addObject: [NSNull null]];
  }
  [newContact setObject: phoneNumbers forKey: @"phone numbers"];
  
  [newContact setObject: [NSNumber numberWithUnsignedChar: bytes[pbpPrimaryNumberOffset]] forKey: @"primary number"];
  
  return 0;
}

@synthesize phone, supportsIM, supportsStreetAddress, supportsFavorites, supportsNotes, groups, dataDelegate, speeds, favorites;
@synthesize toDelete, contactGroupLimit, numberLength;

static NSString *imServices[] = {@"aim", @"yahoo", @"msn", nil};

- (BOOL) supportsIMService: (NSString *) service {
  int i;
  
  for (i = 0 ; imServices[i] ; i++)
    if ([service isEqualToString: imServices[i]])
      return YES;

  return NO;
}

- (void) addFileData: (NSString *) path storeTo: (NSMutableDictionary *) contact withKey: (NSString *) key {
  NSString *psPath = [NSHomeDirectory () stringByAppendingPathComponent: [NSString stringWithFormat: @"Library/Application Support/vxSync/PersistentStore/%@", path]];
  NSData *fileData;
  NSString *error;
  struct stat statinfo;
  
  if (stat ([psPath UTF8String], &statinfo) == -1) {
    vxSync_log3(VXSYNC_LOG_DEBUG, @"archiving data from phone to %s\n", NS2CH(psPath));
    
    fileData = [[phone efs] get_file_data_from: path errorOut: &error];
    if (!fileData) {
      vxSync_log3(VXSYNC_LOG_ERROR, @"can not read file data. reason: %s\n", NS2CH(error));
      
      return;
    }
    
    /* make a local backup */
    /* create the directory if needed */
    [[NSFileManager defaultManager] createDirectoryAtPath: [psPath stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
    [fileData writeToFile: psPath atomically: YES];
  } else 
    fileData = [NSData dataWithContentsOfFile: psPath];
  
  [contact setObject: fileData forKey: key];
}

- (void) writeFileData: (NSString *) path withData: (NSData *) fileData overWrite: (BOOL) overWrite {
  NSString *psPath = [NSHomeDirectory () stringByAppendingPathComponent: [NSString stringWithFormat: @"Library/Application Support/vxSync/PersistentStore/%@", path]];
  struct stat statinfo;

  if (!path)
    return;
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"writing file data to %s. overwrite = %i\n", NS2CH(path), overWrite);
  
  if (overWrite || ([[phone efs] stat: path to: &statinfo] != 0)) {
    if (fileData && (overWrite || stat ([psPath UTF8String], &statinfo) != 0))
      [fileData writeToFile: psPath atomically: YES];
    
    /* read file data from cache if necessary */
    if (!fileData)
      fileData = [NSData dataWithContentsOfFile: psPath];
  
    if (fileData) {
      int fd = [[phone efs] open: path withFlags: O_WRONLY | O_TRUNC | O_CREAT];

      vxSync_log3(VXSYNC_LOG_DEBUG, @"writing file data to %s. fd = %i\n", NS2CH(path), fd);
      
      if (fd == -1)
        return;
    
      [[phone efs] write: fd from: (unsigned char *)[fileData bytes] count: [fileData length]];
      [[phone efs] close: fd];
    }
  }
}

- (void) setupValues {
  /* do nothing */
}

- (void) readSessionData {
  NSDictionary *rootObject = [[NSUserDefaults standardUserDefaults] persistentDomainForName: @"com.enansoft.vxSync.LGPBEntryFile"];
  NSDictionary *phoneData = [rootObject objectForKey: [phone identifier]];
  
  prevSessionLastIndex = phoneData ? [[phoneData objectForKey: @"prevSessionLastIndex"] intValue] : -1;
  prevSessionLastID    = phoneData ? [[phoneData objectForKey: @"prevSessionLastID"] intValue] : -1;
}

- (void) saveSessionData {
  NSMutableDictionary *rootObject = [[[[NSUserDefaults standardUserDefaults] persistentDomainForName: @"com.enansoft.vxSync.LGPBEntryFile"] mutableCopy] autorelease];
  NSMutableDictionary *phoneData = [[[rootObject objectForKey: [phone identifier]] mutableCopy] autorelease];
  
  if (!phoneData)
    phoneData = [NSMutableDictionary dictionary];
  
  [phoneData setObject: [NSNumber numberWithInt: sessionLastIndex] forKey: @"prevSessionLastIndex"];
  [phoneData setObject: [NSNumber numberWithInt: sessionLastID] forKey: @"prevSessionLastID"];
  
  if (!rootObject)
    rootObject = [NSMutableDictionary dictionary];
  
  [rootObject setObject: phoneData forKey: [phone identifier]];
  [[NSUserDefaults standardUserDefaults] setPersistentDomain: rootObject forName: @"com.enansoft.vxSync.LGPBEntryFile"];
}

- (int) getIndex {
  return currentIndex;
}

- (int) setIndex: (unsigned int) i {
  if (i >= contactLimit)
    return -1;

  currentContact = [_contacts objectAtIndex: i];
  
  return (currentIndex = i);
}

- (BOOL) entryIsValid {
  return ![[_contacts objectAtIndex: currentIndex] isKindOfClass: [NSNull class]];
}

- (void) clearEntry {
  int i;

  if ([currentContact isKindOfClass: [NSNull class]])
    return;
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"clearing contact at index: %i\n", currentIndex);
  
  [self setEntryAddress: nil];
  [self setEntryPictureData: nil];
  [self setEntryRingtonePath: nil];
  for (i = 0 ; i < numCount ; i++)
    [self setEntryPhoneNumberOfType: i+1 to: nil];

  _inUseFlag[currentIndex] = 0x20 | (_inUseFlag[currentIndex] & 0xff12);
  [_contacts replaceObjectAtIndex: currentIndex withObject: [NSNull null]];
}

- (void) clearAllEntries {
  int i;

  for (i = 0 ; i < contactLimit ; i++) {
    [self setIndex: i];
    [self clearEntry];
  }

  sessionLastIndex = 0;
}

/* sets entry to defaults -- this method must also be defined in the subclasses */
- (int) prepareNewContact {
  NSMutableArray *emailAddresses, *phoneNumbers;
  NSMutableDictionary *newContact;
  int i;
  
  for (i = 0 ; i < contactLimit ; i++)
    if (!(_inUseFlag[i] & 0x01))
      break;
  
  if (i == contactLimit)
    return -1;
  
  /* update last index to avoid loosing the contact we are just adding */
  sessionLastIndex = (i > sessionLastIndex) ? i : sessionLastIndex;
  
  [self setIndex: i];
  vxSync_log3(VXSYNC_LOG_DEBUG, @"setting up new contact at index: %i with ID = %d\n", currentIndex, sessionLastID + 1);
  
  newContact = [NSMutableDictionary dictionary];
  [newContact setObject: [NSNumber numberWithUnsignedChar: 0] forKey: @"primary number"];
  [newContact setObject: [NSMutableArray arrayWithCapacity: contactGroupLimit] forKey: @"group ids"];
  [newContact setObject: [NSNumber numberWithBool: NO] forKey: @"display as company"];
  emailAddresses = [NSMutableArray arrayWithCapacity: emailCount];
  for (i = 0 ; i < emailCount ; i++)
    [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: i], VXKeyParentIndex, nil]];
  [newContact setObject: emailAddresses forKey: @"email addresses"];
  
  phoneNumbers = [NSMutableArray arrayWithCapacity: numCount];
  for (i = 0 ; i < numCount ; i++)
    [phoneNumbers addObject: [NSNull null]];
  [newContact setObject: phoneNumbers forKey: @"phone numbers"];

  /* the above defaults are phone defaults while will be set by command 0xf12a (no file modifications necessary yet) */
  _inUseFlag[currentIndex] |= 0x0001;
  [self entrySetDirty];
  [self entrySetFileDirty];
  [_contacts replaceObjectAtIndex: currentIndex withObject: newContact];
  currentContact = newContact;
  
  return 0;
}

- (void) setValue: (id) value forKey: (NSString *) key fileChange: (BOOL) fileChange {
  if (!value && [currentContact objectForKey: key]) {
    [currentContact removeObjectForKey: key];
    [self entrySetDirty];
    if (fileChange)
      [self entrySetFileDirty];
  }

  if (!([[currentContact objectForKey: key] isEqual: value] || [currentContact objectForKey: key] == value)) {
    [currentContact setObject: value forKey: key];
    [self entrySetDirty];
    if (fileChange)
      [self entrySetFileDirty];
  }
}

- (NSString *) getEntryName {
  return [[[currentContact objectForKey: @"name"] copy] autorelease];
}

- (void) setEntryName: (NSString *) fullName {
  [self setValue: fullName forKey: @"name" fileChange: NO];
}

- (NSString *) getEntryNotes {
  return [[[currentContact objectForKey: @"notes"] copy] autorelease];
}

- (void) setEntryNotes: (NSString *) notes {
  [self setValue: notes forKey: @"notes" fileChange: NO];
}

- (NSString *) getEntryRingtonePath {
  return [[[currentContact objectForKey: VXKeyRingtonePath] copy] autorelease];
}

- (void) setEntryRingtonePath: (NSString *) ringtonePath {
  [self setValue: nil forKey: VXKeyRingtoneIndex fileChange: NO];
  
  if ([[currentContact objectForKey: VXKeyRingtonePath] hasPrefix: @"set_as_pic_id_dir/"])
    [toDelete addObject: [currentContact objectForKey: VXKeyRingtonePath]];
  
  [self setValue: ringtonePath forKey: VXKeyRingtonePath fileChange: NO];
}

- (NSData *) getEntryPictureData {
  return [[[currentContact objectForKey: @"image"] copy] autorelease];
}

- (void) setEntryPictureData: (NSData *) pictureData {
  NSString *path = nil;

  if (pictureData) {
    /* use the crc32 of the image to ensure a unique filename */
    /* newer phones require picture id images be stored into /set_as_pic_id_dir/ */
    path = ![[phone efs] stat: @"set_as_pic_id_dir" to: NULL] ? @"set_as_pic_id_dir/" : @"brew/mod/10888/";
    path = [path stringByAppendingFormat: @"%d.jpg", crc32 ((u_int8_t *)[pictureData bytes], [pictureData length]) + currentIndex];
  } 

  [self setValue: pictureData forKey: @"image" fileChange: NO];
  [self setValue: path forKey: VXKeyPicturePath fileChange: NO];
}

- (NSArray *) getEntryGroupIDs {
  return [[[currentContact objectForKey: @"group ids"] copy] autorelease];
}

- (void) setEntryGroupIDs: (NSArray *) gIDs {
  [self setValue: [[gIDs copy] autorelease] forKey: @"group ids" fileChange: YES];
}

- (NSDictionary *) getEntryAddress {
  return [[[currentContact objectForKey: @"street address"] copy] autorelease];
}

- (int) setEntryAddress: (NSDictionary *) streetAddress {
  int addressIndex = -1;
  NSDictionary *oldAddress = [currentContact objectForKey: @"street address"];

  if (![self supportsStreetAddress])
    return -1;
  
  if (oldAddress) {
    addressIndex = [[oldAddress objectForKey: VXKeyIndex] intValue];
    [currentContact removeObjectForKey: @"street address"];
  }
  
  if (streetAddress) {
    if (-1 == addressIndex) {
      for (addressIndex = 0 ; addressIndex < contactLimit ; addressIndex++)
        if (!(_inUseFlag[addressIndex] & 0x02))
          break;

      if (addressIndex == contactLimit)
        return -1;
    }
    
    NSMutableDictionary *newAddress = [[streetAddress mutableCopy] autorelease];
    [newAddress setObject: [NSNumber numberWithInt: addressIndex] forKey: VXKeyIndex];
    [self setValue: [[newAddress copy] autorelease] forKey: @"street address" fileChange: addressOffset > -1];
    _inUseFlag[addressIndex] |= 0x12;
  } else if (oldAddress)
    _inUseFlag[addressIndex] = 0x10 | (_inUseFlag[addressIndex] & 0xfffd);
  
  return 0;
}

- (NSArray *) getEntryIM {
  return [[[currentContact objectForKey: @"im"] copy] autorelease];
}

- (int) setEntryIM: (NSDictionary *) im {
  int imIndex = -1;
  NSDictionary *oldIM = [currentContact objectForKey: @"im"];
  NSMutableDictionary *newIM = [[im mutableCopy] autorelease];

  if (![self supportsIM])
    return -1;
  
  if (oldIM) {
    imIndex = [[oldIM objectForKey: VXKeyIndex] intValue];
    [currentContact removeObjectForKey: @"im"];
  } else {
    if (im) {
      for (imIndex = 0 ; imIndex < contactLimit ; imIndex++)
        if (!(_inUseFlag[imIndex] & 0x04))
          break;
      
      if (imIndex == contactLimit)
        return -1;
    }
  }

  [newIM setObject: [NSNumber numberWithInt: imIndex] forKey: VXKeyIndex];
  [self setValue: newIM forKey: @"im" fileChange: NO];

  return 0;
}

- (NSArray *) getEntryPhoneNumbers {
  NSMutableArray *numbers = [NSMutableArray array];
  
  for (id number in [currentContact objectForKey: @"phone numbers"])
    if ([number isKindOfClass: [NSDictionary class]])
      [numbers addObject: [[number copy] autorelease]];
  
  return [[numbers copy] autorelease];
}

- (int) setEntryPhoneNumberOfType: (const unsigned char) type to: (NSDictionary *) numberDict {
  NSMutableDictionary *number;
  int primaryNumber;

  if (![currentContact isKindOfClass: [NSDictionary class]]) {
    vxSync_log3(VXSYNC_LOG_DEBUG, @"setting number for null contact: %i\n", currentIndex);
    return -1;
  }
  
  if (type > 5)
    return -1;

  primaryNumber = [[currentContact objectForKey: @"primary number"] intValue];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"setting number type %i to %s\n", type, NS2CH(numberDict));

  number = [[currentContact objectForKey: @"phone numbers"] objectAtIndex: type - 1];
  if (nil == numberDict && [number isKindOfClass: [NSDictionary class]]) {
    /* delete number */
    for (id speed in [number objectForKey: VXKeySpeedDial])
      [self setSpeedDial: [speed intValue] withContact: 0xffff numberType: 0xff];

    [[currentContact objectForKey: @"phone numbers"] replaceObjectAtIndex: type - 1 withObject: [NSNull null]];

    if (type == primaryNumber) {
      for (number in [currentContact objectForKey: @"phone numbers"])
        if ([number isKindOfClass: [NSDictionary class]])
          break;
      [self setEntryPrimaryNumberType: [[number objectForKey: VXKeyType] intValue]];
    }

    [self entrySetDirty];
  } else if (numberDict && ![numberDict isEqual: number]) {
    [[currentContact objectForKey: @"phone numbers"] replaceObjectAtIndex: type - 1 withObject: [[numberDict copy] autorelease]];

    for (id speed in [numberDict objectForKey: VXKeySpeedDial])
      [self setSpeedDial: [speed intValue] withContact: currentIndex numberType: type];

    /* this is the first phone number so set the primary type */
    if (!primaryNumber)
      [self setEntryPrimaryNumberType: type];

    [self entrySetDirty];
  }

  return 0;
}

- (void) setEntryPrimaryNumberType: (const unsigned char) type {
  if (type > 5)
    return;

  [self setValue: [NSNumber numberWithInt: type] forKey: @"primary number" fileChange: NO];
}

- (int) getEntryPrimaryNumberType {
  return [[currentContact objectForKey: @"primary number"] intValue]; 
}

- (BOOL) entryNumberTypeInUse: (const unsigned char) type {
  if (type > 5)
    return YES;

  return [[[currentContact objectForKey: @"phone numbers"] objectAtIndex: type - 1] isKindOfClass: [NSDictionary class]];
}

- (NSArray *) getEntryEmails {
  NSMutableArray *emails = [NSMutableArray array];
  
  for (id email in [currentContact objectForKey: @"email addresses"])
    if ([email objectForKey: @"value"])
      [emails addObject: [[email copy] autorelease]];
  
  return [NSArray arrayWithArray: emails];
}

- (int) setEntryEmail: (NSString *) email index: (int) aIndex {  
  NSMutableDictionary *emailAddress;

  if (aIndex >= emailCount)
    return -1;
  
  emailAddress = [[currentContact objectForKey: @"email addresses"] objectAtIndex: aIndex];
  if (!emailAddress)
    return -1;
  
  if (nil == email && [emailAddress objectForKey: @"value"]) {
      [emailAddress removeObjectForKey: @"value"];
  } else if (email) {
    if (![[emailAddress objectForKey: @"value"] isEqual: email]) {
      [emailAddress setObject: [[email copy] autorelease] forKey: @"value"];
      [self entrySetDirty];
    }
  }

  return 0;
}

- (int) getEntryFirstFreeEmailIndex {
  int i = 0;
  
  for (id email in [currentContact objectForKey: @"email addresses"]) {
    if (![email objectForKey: @"value"])
      return i;
    i++;
  }
  
  return -1;
}

- (BOOL) getEntryDisplayAsCompany {
  return [[currentContact objectForKey: @"display as company"] boolValue];
}

- (void) setEntryDisplayAsCompany: (BOOL) value {
  [self setValue: [NSNumber numberWithBool: value] forKey: @"display as company" fileChange: YES];
}

- (void) entrySetDirty {
  _inUseFlag[currentIndex] |= 0x80;
}

- (void) entrySetFileDirty {
  _inUseFlag[currentIndex] |= 0x40;
}

- (int) readRecordID {
  int fd = [[phone efs] open: @"pim/record_id.dat" withFlags: O_RDONLY];
  if (fd < -1)
    return -1;
  
  [[phone efs] read: fd to: (unsigned char *)&sessionLastID count: 4];
  [[phone efs] close: fd];
  
  sessionLastID = OSSwapLittleToHostInt32 (sessionLastID);
  
  return 0;
}

- (int) protocolDeleteEntry: (int) entryIndex {
  int ret;
  vxSync_log3(VXSYNC_LOG_INFO, @"deleting record at index: %i\n", entryIndex);

  memset (bytes, 0, 1024);
  bytes[0] = 0xf1;
  bytes[1] = 0x2b;
  OSWriteLittleInt16 (bytes, 2, entryIndex);

  ret = [[phone efs] send_recv_message: bytes sendLength: 4 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  
  return ret != -1;
}

- (int) protocolCommitEntry: (int) entryIndex {
  int ret;
  NSDictionary *contact = [_contacts objectAtIndex: entryIndex];

  memset (bytes, 0, 600);
  bytes[0] = 0xf1;
  bytes[1] = 0x2a;
  OSWriteLittleInt16 (bytes, 2, entryIndex);
  
  [[contact objectForKey: @"name"] getCString: (char *)(bytes + pbpNameOffset) maxLength: nameLength encoding: nameEncoding];
  
  /* HACK -- sometimes writing an entry can cause the group ids to be erased. this will force them to be rewritten */
  if ([[contact objectForKey: @"group ids"] count])
    _inUseFlag[entryIndex] |= 0x40;

  for (id emailAddress in [contact objectForKey: @"email addresses"]) {
    int emailIndex = [[emailAddress objectForKey: VXKeyParentIndex] intValue];
    [[emailAddress objectForKey: @"value"] getCString: (char *)(bytes + pbpEmailOffset + emailIndex * emailLength) maxLength: emailLength encoding: NSISOLatin1StringEncoding];
  }

  for (id phoneNumber in [contact objectForKey: @"phone numbers"]) {
    if ([phoneNumber isKindOfClass: [NSNull class]])
      continue;

    NSString *cleanedNumber = unformatNumber ([phoneNumber objectForKey: @"value"]);
    int typeIndex      = [[phoneNumber objectForKey: VXKeyType] intValue] - 1;
    
    [cleanedNumber getCString: (char *)(bytes + pbpNumberOffset + typeIndex * numberLength) maxLength: numberLength encoding: NSASCIIStringEncoding];
  }

  bytes[pbpPrimaryNumberOffset] = [[contact objectForKey: @"primary number"] unsignedCharValue];
  /* set the picture index (to avoid unsetting it) */
  OSWriteLittleInt16 (bytes, pbpNumberOffset - 2, [contact objectForKey: VXKeyPicturePath] ? 0x64 : 0xffff);
  if ([contact objectForKey: VXKeyRingtoneIndex])
    OSWriteLittleInt16 (bytes, pbpNumberOffset - 6, [[contact objectForKey: VXKeyRingtoneIndex] unsignedShortValue]);
  else
    OSWriteLittleInt16 (bytes, pbpNumberOffset - 6, [contact objectForKey: VXKeyRingtonePath] ? 0x64 : 0xffff);
  
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: 754], @"writing phonebook data:\n");
  ret = [[phone efs] send_recv_message: bytes sendLength: 600 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  
  [self writeRingerID: entryIndex];
  [self writePictureID: entryIndex];

  return ret != -1;
}

- (int) commitChanges {
  int i, j, fd;
  
  /* cleanup files that are no longer needed */
  for (id deletedfile in toDelete)
    [[phone efs] unlink: deletedfile];
  [toDelete removeAllObjects];
  
  [self commitGroups];

  for (i = 0 ; i < contactLimit ; i++) {
    vxSync_log3(VXSYNC_LOG_DEBUG, @"_inUseFlag[%d] = %02x\n", i, _inUseFlag[i]);

    if (_inUseFlag[i] & 0x20)
      [self protocolDeleteEntry: i];
    if ((_inUseFlag[i] & 0x81) == 0x81)
      [self protocolCommitEntry: i];
  }
  
  /* write modified contacts */
  fd = [[phone efs] open: VXPBEntryPath withFlags: O_RDWR];
  if (-1 == fd)
    return -1;
      
  for (i = 0 ; i < contactLimit ; i++) {
    if ((_inUseFlag[i] & 0x41) == 0x41) {
      [[phone efs] setRequiresReboot: YES];

      NSDictionary *contact = [_contacts objectAtIndex: i];

      vxSync_log3(VXSYNC_LOG_DEBUG, @"updating file data for contact: %s\n", NS2CH(contact));
      
      /* need to modify something in the pbentry.dat file */
      [[phone efs] lseek: fd toOffset: i * recordLength whence: SEEK_SET];
      [[phone efs] read: fd to: bytes count: recordLength];

      vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: recordLength], @"original file data for contact %i:\n", i);

      /* protocol doesn't support reading street addresses. read them from pbaddress.dat */
      if (addressOffset > -1) {
        UInt16 addressIndex = 0xffff;
        if ([[contact objectForKey: @"street address"] count])
          addressIndex = [[[contact objectForKey: @"street address"] objectForKey: VXKeyIndex] unsignedIntValue];
          
        OSWriteLittleInt16 (bytes, addressOffset, addressIndex);
      }
      bytes[recordLength - 7] = [[contact objectForKey: @"display as company"] boolValue] ? 0x01 : 0x00;
      
      NSArray *groupIDs = [contact objectForKey: @"group ids"];
      for (j = 0 ; j < contactGroupLimit ; j++)
        OSWriteLittleInt16 (bytes, groupOffset + j * 2, (j < [groupIDs count]) ? [[groupIDs objectAtIndex: j] unsignedIntValue] : 0);
      
      [[phone efs] lseek: fd toOffset: i * recordLength whence: SEEK_SET];
      
      vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: recordLength], @"submitting modification to file data for %i:\n", i);
      
      [[phone efs] write: fd from: bytes count: recordLength];
    }
    
    _inUseFlag[i] &= 0xff1f;
  }
  
  [[phone efs] close: fd];

  [self commitStreetAddresses];
  (void)[self commitSpeeds];
  
  /* finally, save session data */
  [self saveSessionData];

  return 0;
}
@end

@implementation LGPBStandard2
+ (id) phonebookWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBStandard2 alloc] initWithPhone: phoneIn] autorelease];
}

- (void) setupValues {
  [super setupValues];
  pbpNameOffset          =  10;
  nameLength             =  33; /* bytes */
  pbpEmailOffset         =  45;
  pbpNumberOffset        = 149;
  pbpPrimaryNumberOffset = 394;
  self.numberLength      =  49;
  
  idOffset         =  23;
  nameEncoding     =  NSISOLatin1StringEncoding;
  groupOffset      =  62;
  ringtoneIDOffset = 162;
  pictureIDOffset  = 164;
  emailCount       =   2;
  emailLength      =  49;
  numCount         =   5;
  addressOffset    =  -1; /* not supported in this file format */
  recordLength     = 256;
  contactGroupLimit    =   1;
  [self setSupportsIM: NO];
  [self setSupportsNotes: NO];
  [self setSupportsFavorites: NO]; /* the Versa DOES support favorites */
  [self setSupportsStreetAddress: NO];
}
@end

@implementation LGPBExtended2
+ (id) phonebookWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBExtended2 alloc] initWithPhone: phoneIn] autorelease];
}

- (void) setupValues {
  [super setupValues];
  
  idOffset           =  24;
  addressOffset      = 242;
  recordLength       = 512;
  groupOffset        =  64;
  ringtoneIDOffset   = 222;
  pictureIDOffset    = 224;
  contactGroupLimit  =  30;
  addressEntryLength = 255;

  [self setSupportsFavorites: YES];
  [self setSupportsStreetAddress: YES];
}
@end

@implementation LGPBExtended2v2
+ (id) phonebookWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBExtended2v2 alloc] initWithPhone: phoneIn] autorelease];
}

- (void) setupValues {
  [super setupValues];

  addressOffset      =  -1;
  addressEntryLength = 256;
  [self setSupportsIM: YES];
}

- (int) protocolCommitEntry: (int) entryIndex {
  int ret, j;
  NSDictionary *contact = [_contacts objectAtIndex: entryIndex];
  NSDictionary *streetAddress = [contact objectForKey: @"street address"];
  NSDictionary *im = [contact objectForKey: @"im"];
  struct lg_pbv1_standard_choct *pbData = (struct lg_pbv1_standard_choct *) bytes;
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"writing contact: %s\n", NS2CH(contact));
  
  memset (bytes, 0, sizeof (struct lg_pbv1_standard_choct));
  pbData->command       = 0xf1;
  pbData->option        = 0x2a;
  pbData->entry_index   = OSSwapHostToLittleInt16 (entryIndex);
  
  [[contact objectForKey: @"name"] getCString: pbData->name maxLength: sizeof(pbData->name) encoding: nameEncoding];

  /* HACK -- sometimes writing an entry can cause the group ids to be erased. this will force them to be rewritten */
  if ([[contact objectForKey: @"group ids"] count])
    _inUseFlag[entryIndex] |= 0x40;

  for (id emailAddress in [contact objectForKey: @"email addresses"]) {
    int emailIndex = [[emailAddress objectForKey: VXKeyParentIndex] intValue];
    [[emailAddress objectForKey: @"value"] getCString: pbData->emails[emailIndex] maxLength: sizeof (pbData->emails[emailIndex]) encoding: NSISOLatin1StringEncoding];
  }
  
  for (id phoneNumber in [contact objectForKey: @"phone numbers"]) {
    if ([phoneNumber isKindOfClass: [NSNull class]])
      continue;
    
    NSString *cleanedNumber = unformatNumber ([phoneNumber objectForKey: @"value"]);
    int typeIndex      = [[phoneNumber objectForKey: VXKeyType] intValue] - 1;
    
    [cleanedNumber getCString: pbData->numbers[typeIndex] maxLength: sizeof (pbData->numbers[typeIndex]) encoding: NSASCIIStringEncoding];
  }
  pbData->primary_number = OSSwapHostToLittleInt16 ([[contact objectForKey: @"primary number"] unsignedShortValue]);
  [[NSDate date] lgDate: pbData->mod_date];
  
  if (streetAddress) {
    [[streetAddress objectForKey: @"street"] getCString: pbData->street maxLength: sizeof (pbData->street) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"postal code"] getCString: pbData->zip maxLength: sizeof (pbData->zip) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"city"] getCString: pbData->city maxLength: sizeof (pbData->city) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"state"] getCString: pbData->state maxLength: sizeof (pbData->state) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"country"] getCString: pbData->country maxLength: sizeof (pbData->country) encoding: NSISOLatin1StringEncoding];
  }
  
  if (im) {
    for (j = 0 ; imServices[j] ; j++)
      if ([imServices[j] isEqualToString: [im objectForKey: @"service"]])
        break;
    if (imServices[j])
      pbData->im_service = OSSwapHostToLittleInt16 (j);

    [[im objectForKey: @"user"] getCString: pbData->user maxLength: sizeof (pbData->user) encoding: NSISOLatin1StringEncoding];
  }

  if ([contact objectForKey: VXKeyRingtoneIndex])
    pbData->ringtone_index = OSSwapHostToLittleInt16 ([[contact objectForKey: VXKeyRingtoneIndex] unsignedShortValue]);
  else
    pbData->ringtone_index = OSSwapHostToLittleInt16 ([contact objectForKey: VXKeyRingtonePath] ? 0x0064 : 0xffff);

  /* set the picture index (to avoid unsetting it) */
  pbData->picture_index = OSSwapHostToLittleInt16 ([contact objectForKey: VXKeyPicturePath] ? 0x0064 : 0xffff);

  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: 754], @"writing phonebook data:\n");
  
  ret = [[phone efs] send_recv_message: bytes sendLength: 754 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];

  [self writeRingerID: entryIndex];
  [self writePictureID: entryIndex];
  
  return ret != -1;
}

- (int) protocolReadEntry: (int) entryIndex storeIn: (NSMutableDictionary *) newContact {
  int j;
  struct lg_pbv1_standard_choct *pbData = (struct lg_pbv1_standard_choct *) bytes;
  
  memset (bytes, 0, sizeof (struct lg_pbv1_standard_choct));
  pbData->command     = 0xf1;
  pbData->option      = 0x29;
  pbData->entry_index = OSSwapHostToLittleInt16 (entryIndex);
  
  int ret = [[phone efs] send_recv_message: bytes sendLength: 4 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: ret], @"phonebook data for contact %i:\n", entryIndex);
  
  [newContact setObject: stringFromBuffer((unsigned char *)pbData->name, sizeof (pbData->name), nameEncoding) forKey: @"name"];
  NSMutableArray *emailAddresses = [NSMutableArray arrayWithCapacity: emailCount];
  for (j = 0 ; j < emailCount ; j++) {
    NSString *emailAddress = stringFromBuffer((unsigned char *)pbData->emails[j], sizeof (pbData->emails[j]), NSISOLatin1StringEncoding);
    if ([emailAddress length])
      [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: emailAddress, @"value", [NSNumber numberWithInt: j], VXKeyParentIndex, nil]];
    else 
      [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: j], VXKeyParentIndex, nil]];
  }
  [newContact setObject: emailAddresses forKey: @"email addresses"];
  
  NSArray *contactSpeeds = [self speedsForContact: entryIndex];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"speeds for contact: %s\n", NS2CH(contactSpeeds));
  
  NSMutableArray *phoneNumbers = [NSMutableArray arrayWithCapacity: numCount];
  for (j = 0 ; j < numCount ; j++) {
    NSString *phoneNumber = formattedNumber (pbData->numbers[j]);

    if ([phoneNumber length]) {
      NSMutableArray *_speeds = [NSMutableArray array];
      for (id speed in contactSpeeds) {
        if ([[speed objectForKey: VXKeyType] intValue] == (j + 1))
          [_speeds addObject: [speed objectForKey: VXKeyIndex]];
      }
      
      NSMutableDictionary *newNumber = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                        EntityNumber,                            ISyncRecordEntityNameKey,
                                        phoneNumber,                             @"value",
                                        [[numberTypes[j + 1] copy] autorelease], @"type",
                                        [NSNumber numberWithInt: j + 1],         VXKeyType,
                                        nil];
      if ([_speeds count])
        [newNumber setObject: _speeds forKey: VXKeySpeedDial];
      [phoneNumbers addObject: newNumber];
    } else
      [phoneNumbers addObject: [NSNull null]];
  }
  [newContact setObject: phoneNumbers forKey: @"phone numbers"];
  [newContact setObject: [NSNumber numberWithUnsignedChar: OSSwapLittleToHostInt16 (pbData->primary_number)] forKey: @"primary number"];
  
  NSMutableDictionary *address = [NSMutableDictionary dictionary];
  
  if (strlen (pbData->street))
    [address setObject: stringFromBuffer((unsigned char *)pbData->street, sizeof (pbData->street), NSISOLatin1StringEncoding) forKey: @"street"];
  if (strlen (pbData->city))
    [address setObject: stringFromBuffer((unsigned char *)pbData->city, sizeof (pbData->city), NSISOLatin1StringEncoding) forKey: @"city"];
  if (strlen (pbData->country))
    [address setObject: stringFromBuffer((unsigned char *)pbData->country, sizeof (pbData->country), NSISOLatin1StringEncoding) forKey: @"country"];
  if (strlen (pbData->zip))
    [address setObject: stringFromBuffer((unsigned char *)pbData->zip, sizeof (pbData->zip), NSISOLatin1StringEncoding) forKey: @"postal code"];
  if (strlen (pbData->state))
    [address setObject: stringFromBuffer((unsigned char *)pbData->state, sizeof (pbData->state), NSISOLatin1StringEncoding) forKey: @"state"];
  if ([[address allKeys] count]) {
    [address setObject: EntityAddress forKey: ISyncRecordEntityNameKey];
    [newContact setObject: [[address copy] autorelease] forKey: @"street address"];
  }

  if (OSSwapLittleToHostInt16 (pbData->im_service) < 3 && strlen (pbData->user)) {
    NSMutableDictionary *im = [NSMutableDictionary dictionary];
    [im setObject: EntityIM forKey: ISyncRecordEntityNameKey];
    [im setObject: imServices[OSSwapLittleToHostInt16 (pbData->im_service)] forKey: @"service"];
    [im setObject: stringFromBuffer((unsigned char *)pbData->user, sizeof (pbData->user), NSISOLatin1StringEncoding) forKey: @"user"];
    [newContact setObject: [[im copy] autorelease] forKey:@"im"];
  }

  return 0;
}

- (int) commitStreetAddresses {
  return 0;
}

@end

@implementation LGPBExtended2v3
+ (id) phonebookWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBExtended2v3 alloc] initWithPhone: phoneIn] autorelease];
}

- (void) setupValues {
  [super setupValues];
  
  addressOffset      =  -1;
  [self setSupportsIM: YES];
  [self setSupportsNotes: YES];
}

- (int) protocolCommitEntry: (int) entryIndex {
  int ret, j;
  NSDictionary *contact = [_contacts objectAtIndex: entryIndex];
  NSDictionary *streetAddress = [contact objectForKey: @"street address"];
  NSDictionary *im = [contact objectForKey: @"im"];
  struct lg_pbv1_standard_accolade *pbData = (struct lg_pbv1_standard_accolade *) bytes;
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"writing contact: %s\n", NS2CH(contact));
  
  memset (bytes, 0, sizeof (struct lg_pbv1_standard_accolade));
  pbData->command       = 0xf1;
  pbData->option        = 0x2a;
  pbData->entry_index   = OSSwapHostToLittleInt16 (entryIndex);
  
  [[contact objectForKey: @"name"] getCString: pbData->name maxLength: sizeof(pbData->name) encoding: nameEncoding];
  
  /* HACK -- sometimes writing an entry can cause the group ids to be erased. this will force them to be rewritten */
  if ([[contact objectForKey: @"group ids"] count])
    _inUseFlag[entryIndex] |= 0x40;
  
  for (id emailAddress in [contact objectForKey: @"email addresses"]) {
    int emailIndex = [[emailAddress objectForKey: VXKeyParentIndex] intValue];
    [[emailAddress objectForKey: @"value"] getCString: pbData->emails[emailIndex] maxLength: sizeof (pbData->emails[emailIndex]) encoding: NSISOLatin1StringEncoding];
  }
  
  for (id phoneNumber in [contact objectForKey: @"phone numbers"]) {
    if ([phoneNumber isKindOfClass: [NSNull class]])
      continue;
    
    NSString *cleanedNumber = unformatNumber ([phoneNumber objectForKey: @"value"]);
    int typeIndex      = [[phoneNumber objectForKey: VXKeyType] intValue] - 1;
    
    [cleanedNumber getCString: pbData->numbers[typeIndex] maxLength: sizeof (pbData->numbers[typeIndex]) encoding: NSASCIIStringEncoding];
  }
  pbData->primary_number = OSSwapHostToLittleInt16 ([[contact objectForKey: @"primary number"] unsignedShortValue]);
  [[NSDate date] lgDate: pbData->mod_date];
  
  if (streetAddress) {
    [[streetAddress objectForKey: @"street"] getCString: pbData->street maxLength: sizeof (pbData->street) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"postal code"] getCString: pbData->zip maxLength: sizeof (pbData->zip) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"city"] getCString: pbData->city maxLength: sizeof (pbData->city) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"state"] getCString: pbData->state maxLength: sizeof (pbData->state) encoding: NSISOLatin1StringEncoding];
    [[streetAddress objectForKey: @"country"] getCString: pbData->country maxLength: sizeof (pbData->country) encoding: NSISOLatin1StringEncoding];
  }
  
  if (im) {
    for (j = 0 ; imServices[j] ; j++)
      if ([imServices[j] isEqualToString: [im objectForKey: @"service"]])
        break;
    if (imServices[j])
      pbData->im_service = OSSwapHostToLittleInt16 (j);
    
    [[im objectForKey: @"user"] getCString: pbData->user maxLength: sizeof (pbData->user) encoding: NSISOLatin1StringEncoding];
  }

  if ([contact objectForKey: @"notes"])
    [[contact objectForKey: @"notes"] getCString: pbData->note maxLength: sizeof (pbData->note) encoding: NSISOLatin1StringEncoding];
  
  if ([contact objectForKey: VXKeyRingtoneIndex])
    pbData->ringtone_index = OSSwapHostToLittleInt16 ([[contact objectForKey: VXKeyRingtoneIndex] unsignedShortValue]);
  else
    pbData->ringtone_index = OSSwapHostToLittleInt16 ([contact objectForKey: VXKeyRingtonePath] ? 0x0064 : 0xffff);
  
  /* set the picture index (to avoid unsetting it) */
  pbData->picture_index = OSSwapHostToLittleInt16 ([contact objectForKey: VXKeyPicturePath] ? 0x0064 : 0xffff);
  
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: 754], @"writing phonebook data:\n");
  
  ret = [[phone efs] send_recv_message: bytes sendLength: 754 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  
  [self writeRingerID: entryIndex];
  [self writePictureID: entryIndex];
  
  return ret != -1;
}

- (int) protocolReadEntry: (int) entryIndex storeIn: (NSMutableDictionary *) newContact {
  int j;
  struct lg_pbv1_standard_accolade *pbData = (struct lg_pbv1_standard_accolade *) bytes;
  
  memset (bytes, 0, sizeof (struct lg_pbv1_standard_accolade));
  pbData->command     = 0xf1;
  pbData->option      = 0x29;
  pbData->entry_index = OSSwapHostToLittleInt16 (entryIndex);
  
  int ret = [[phone efs] send_recv_message: bytes sendLength: 4 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: ret], @"phonebook data for contact %i:\n", entryIndex);
  
  /* TODO -- separate work and home emails here.... in fact, do this whole thing in a lot cleaner way */
  [newContact setObject: stringFromBuffer((unsigned char *)pbData->name, sizeof (pbData->name), nameEncoding) forKey: @"name"];
  NSMutableArray *emailAddresses = [NSMutableArray arrayWithCapacity: emailCount];
  for (j = 0 ; j < emailCount ; j++) {
    NSString *emailAddress = stringFromBuffer((unsigned char *)pbData->emails[j], sizeof (pbData->emails[j]), NSISOLatin1StringEncoding);
    if ([emailAddress length])
      [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: emailAddress, @"value", [NSNumber numberWithInt: j], VXKeyParentIndex, nil]];
    else 
      [emailAddresses addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: j], VXKeyParentIndex, nil]];
  }
  [newContact setObject: emailAddresses forKey: @"email addresses"];
  
  NSArray *contactSpeeds = [self speedsForContact: entryIndex];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"speeds for contact: %s\n", NS2CH(contactSpeeds));
  
  NSMutableArray *phoneNumbers = [NSMutableArray arrayWithCapacity: numCount];
  for (j = 0 ; j < numCount ; j++) {
    NSString *phoneNumber = formattedNumber (pbData->numbers[j]);
    
    if ([phoneNumber length]) {
      NSMutableArray *_speeds = [NSMutableArray array];
      for (id speed in contactSpeeds) {
        if ([[speed objectForKey: VXKeyType] intValue] == (j + 1))
          [_speeds addObject: [speed objectForKey: VXKeyIndex]];
      }
      
      NSMutableDictionary *newNumber = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                        EntityNumber,                            ISyncRecordEntityNameKey,
                                        phoneNumber,                             @"value",
                                        [[numberTypes[j + 1] copy] autorelease], @"type",
                                        [NSNumber numberWithInt: j + 1],         VXKeyType,
                                        nil];
      if ([_speeds count])
        [newNumber setObject: _speeds forKey: VXKeySpeedDial];
      [phoneNumbers addObject: newNumber];
    } else
      [phoneNumbers addObject: [NSNull null]];
  }
  [newContact setObject: phoneNumbers forKey: @"phone numbers"];
  [newContact setObject: [NSNumber numberWithUnsignedChar: OSSwapLittleToHostInt16 (pbData->primary_number)] forKey: @"primary number"];
  
  NSMutableDictionary *address = [NSMutableDictionary dictionary];
  
  if (strlen (pbData->street))
    [address setObject: stringFromBuffer((unsigned char *)pbData->street, sizeof (pbData->street), NSISOLatin1StringEncoding) forKey: @"street"];
  if (strlen (pbData->city))
    [address setObject: stringFromBuffer((unsigned char *)pbData->city, sizeof (pbData->city), NSISOLatin1StringEncoding) forKey: @"city"];
  if (strlen (pbData->country))
    [address setObject: stringFromBuffer((unsigned char *)pbData->country, sizeof (pbData->country), NSISOLatin1StringEncoding) forKey: @"country"];
  if (strlen (pbData->zip))
    [address setObject: stringFromBuffer((unsigned char *)pbData->zip, sizeof (pbData->zip), NSISOLatin1StringEncoding) forKey: @"postal code"];
  if (strlen (pbData->state))
    [address setObject: stringFromBuffer((unsigned char *)pbData->state, sizeof (pbData->state), NSISOLatin1StringEncoding) forKey: @"state"];
  if ([[address allKeys] count]) {
    [address setObject: EntityAddress forKey: ISyncRecordEntityNameKey];
    [newContact setObject: [[address copy] autorelease] forKey: @"street address"];
  }
  
  if (OSSwapLittleToHostInt16 (pbData->im_service) < 3 && strlen (pbData->user)) {
    NSMutableDictionary *im = [NSMutableDictionary dictionary];
    [im setObject: EntityIM forKey: ISyncRecordEntityNameKey];
    [im setObject: imServices[OSSwapLittleToHostInt16 (pbData->im_service)] forKey: @"service"];
    [im setObject: stringFromBuffer((unsigned char *)pbData->user, sizeof (pbData->user), NSISOLatin1StringEncoding) forKey: @"user"];
    [newContact setObject: [[im copy] autorelease] forKey:@"im"];
  }

  if (strlen (pbData->note))
    [newContact setObject: stringFromBuffer((unsigned char *)pbData->note, sizeof (pbData->note), NSISOLatin1StringEncoding) forKey: @"notes"];
  
  return 0;
}

- (int) commitStreetAddresses {
  return 0;
}

@end

@implementation LGPBStandardUnicode2
+ (id) phonebookWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBStandardUnicode2 alloc] initWithPhone: phoneIn] autorelease];
}

- (void) setupValues {
  [super setupValues];

  nameEncoding           =  VXUTF16LEStringEncoding;
  nameLength             =  66;
  pbpEmailOffset         =  78;
  pbpNumberOffset        = 182;
  pbpPrimaryNumberOffset = 427;

  groupOffset      =  95;
  ringtoneIDOffset = 195;
  pictureIDOffset  = 197;
}
@end
