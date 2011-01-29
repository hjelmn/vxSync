/* (-*- objc -*-)
 * vxSync: LGPBGroupFile.m
 * (C) 2010-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "LGPBGroupFile.h"

static NSInteger groupIDcompare (id group1, id group2, void *context) {
  return [[group1 objectForKey: VXKeyPhoneIdentifier] compare: [group2 objectForKey: VXKeyPhoneIdentifier]];
}

@interface LGPBEntryFile (hidden)
- (void) addFileData: (NSString *) path storeTo: (NSMutableDictionary *) contact withKey: (NSString *) key;
- (void) writeFileData: (NSString *) path withData: (NSData *) fileData overWrite: (BOOL) overWrite;

- (int) readID: (NSString *) fileName storeIn: (NSMutableDictionary *) dict dataKey: (NSString *) dataKey pathKey: (NSString *) pathKey entryIndex: (int) entryIndex;
- (int) writeID: (NSString *) fileName path: (NSString *) path fileData: (NSData *) data entryIndex: (int) entryIndex;
- (int) writeGroupPictureID: (int) entryIndex;

- (void) setGroupPicturePath: (NSMutableDictionary *) group;
@end

@implementation LGPBEntryFile (Groups)

- (int) readGroups {
  NSString *error = nil;
  NSData *groupsData;
  unsigned char *groupsBytes;
  int i, nGroups, groupSize, groupIDOffset, groupNameLength;

  [self setGroups: [NSMutableArray arrayWithCapacity: groupLimit]];
  
  groupsData = [[phone efs] get_file_data_from: VXPBGroupPath errorOut: &error];
  if (!groupsData || [groupsData length] < sizeof (struct lg_group)) {
    if (error)
      vxSync_log3(VXSYNC_LOG_ERROR, @"could not load file data from %s. reason: %s\n", NS2CH(VXPBGroupPath), NS2CH(error));
    
    return -1;
  }
  
  groupsBytes = (unsigned char *)[groupsData bytes];
  
  switch ([phone formatForEntity: EntityGroup]) {
    case LGGroupFormat1:
      groupSize  = (VXUTF16LEStringEncoding == nameEncoding) ? 70 : 36;
      groupIDOffset   = (VXUTF16LEStringEncoding == nameEncoding) ? 66 : 33;
      groupNameLength = (VXUTF16LEStringEncoding == nameEncoding) ? 66 : 33;
      break;
    case LGGroupFormat2:
      groupSize  = 38;
      groupIDOffset   = 33;
      groupNameLength = 33;
      break;
    case LGGroupFormat3:
      groupSize  = 39;
      groupIDOffset   = 34;
      groupNameLength = 34;
      break;
    default:
      vxSync_log3(VXSYNC_LOG_WARNING, @"unknown file format: %i\n", [phone formatForEntity: EntityGroup]);
      return -1;
  }
  
  nGroups = [groupsData length] / groupSize;
  
  vxSync_log3_data(VXSYNC_LOG_DEBUG, groupsData, @"group data\n");
  
  for (i = 0 ; i < nGroups ; i++, groupsBytes += groupSize) {    
    u_int16_t groupID = OSReadLittleInt16 (groupsBytes, groupIDOffset);
    NSString *name    = (groupID > 0) ? stringFromBuffer(groupsBytes, groupNameLength, nameEncoding) : nil;

    if (name && groupID) {
      NSMutableDictionary *newDict = [NSMutableDictionary dictionary];
      
      [newDict setObject: EntityGroup forKey: RecordEntityName];
      [newDict setObject: name forKey: @"name"];
      [newDict setObject: [NSNumber numberWithShort: groupID] forKey: VXKeyPhoneIdentifier];
      [dataDelegate getIdentifierForRecord: newDict compareKeys: [NSArray arrayWithObject: VXKeyPhoneIdentifier]];
      
      vxSync_log3(VXSYNC_LOG_INFO, @"read group: %s\n", NS2CH(newDict));

      /* older phones don't support group pictures. read the picture from the ps in these cases */
      if ([phone formatForEntity: EntityGroup] != LGGroupFormat1) {
        u_int16_t pictureFlag = OSReadLittleInt16 (groupsBytes, groupIDOffset + 3);
        
        if (pictureFlag)
          [self readID: VXPBGroupPIXPath storeIn: newDict dataKey: @"image" pathKey: VXKeyPicturePath entryIndex: i];
      } else {
        NSDictionary *oldRecord = [dataDelegate findRecordWithIdentifier: [newDict objectForKey: VXKeyIdentifier] entityName: EntityGroup];

        if ([oldRecord objectForKey: @"image"]) {
          [newDict setObject: [oldRecord objectForKey: @"image"] forKey: @"image"];
          [newDict setObject: [oldRecord objectForKey: VXKeyPicturePath] forKey: VXKeyPicturePath];
        }
      }

      [groups addObject: newDict];
    }
  }

  [groups sortUsingFunction: groupIDcompare context: nil];
  
  /* groups might not be in sorted order so sort them now */
  return 0;
}

- (int) commitGroups {
  int i, ret, groupSize, groupIDOffset, groupNameLength;
  unsigned char *groupBytes;
  NSMutableData *groupData;
  NSData *nameData;

  if ([phone formatForEntity: EntityGroup] != LGGroupFormat1 && [[phone efs] stat: VXPBGroupPIXPath to: NULL] != 0) {
    int groupPIX = [[phone efs] open: VXPBGroupPIXPath withFlags: O_RDWR | O_CREAT, 0644];
    memset (bytes, 0xff, 255);
    
    if (groupPIX > -1)
      for (i = 0 ; i < groupLimit ; i++)
        [[phone efs] write: groupPIX from: bytes count: 255];

    [[phone efs] close: groupPIX];
  }

  switch ([phone formatForEntity: EntityGroup]) {
    case LGGroupFormat1:
      groupSize  = (VXUTF16LEStringEncoding == nameEncoding) ? 70 : 36;
      groupIDOffset   = (VXUTF16LEStringEncoding == nameEncoding) ? 66 : 33;
      groupNameLength = (VXUTF16LEStringEncoding == nameEncoding) ? 66 : 33;
      break;
    case LGGroupFormat2:
      groupSize  = 38;
      groupIDOffset   = 33;
      groupNameLength = 33;
      break;
    case LGGroupFormat3:
      groupSize  = 39;
      groupIDOffset   = 34;
      groupNameLength = 34;
      break;
    default:
      vxSync_log3(VXSYNC_LOG_WARNING, @"unknown file format: %i\n", [phone formatForEntity: EntityGroup]);
      return -1;
  }
  
  groupData = [NSMutableData dataWithLength: groupLimit * groupSize];
  if (!groupData) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not allocate space for group buffer: reason = %s\n", strerror(errno));
    return -1;
  }
  
  groupBytes = [groupData mutableBytes];
  i = 0;
  
  for (id group in groups) {
    if (groupLimit == i)
      break;
    
    vxSync_log3(VXSYNC_LOG_DATA, @"commiting group: %s at index: %d\n", NS2CH([group objectForKey: @"name"]), i);
    
    if ([phone formatForEntity: EntityGroup] != LGGroupFormat1) {
      u_int16_t pictureFlag = [group objectForKey: @"image"] ? 0x64 : 0x00;
      
      OSWriteLittleInt16 (groupBytes, groupIDOffset + 3, pictureFlag);

      [self writeGroupPictureID: i];
    }
    
    OSWriteLittleInt16 (groupBytes, groupIDOffset, [[group objectForKey: VXKeyPhoneIdentifier] unsignedShortValue]);
    nameData = [[group objectForKey: @"name"] dataUsingEncoding: nameEncoding];
    [nameData getBytes: groupBytes length: groupNameLength];
    groupBytes[groupIDOffset + 2] = 1; /* this is probably NOT a deletability flag! */
    
    i++;
    groupBytes += groupSize;
  }
  
  vxSync_log3_data(VXSYNC_LOG_DATA, groupData, @"writing %s:\n", NS2CH(VXPBGroupPath));
  
  ret = [[phone efs] write_file_data: groupData to: VXPBGroupPath];
  
  return ret > 0 ? 0 : -1;
}

- (int) writeGroupPictureID: (int) entryIndex {
  NSDictionary *group = [groups objectAtIndex: entryIndex];
  return [self writeID: VXPBGroupPIXPath path: [group objectForKey: VXKeyPicturePath] fileData: [group objectForKey: @"image"] entryIndex: entryIndex];
}

- (int) deleteGroup: (NSDictionary *) record {
  return [self modifyGroup: nil recordOut: nil identifier: [record objectForKey: VXKeyIdentifier] isNew: NO];
}

- (int) modifyGroup: (NSDictionary *) record recordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew {
  NSArray *group;
  NSMutableDictionary *newGroup = nil, *oldGroup = nil;
  int firstFree = 1;
  
  if (!isNew) {
    group = [groups filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"%K == %@", VXKeyIdentifier, identifier]];
    if ([group count] != 1) {
      vxSync_log3(VXSYNC_LOG_WARNING, @"ack, more than one group has identifier = %s: %i\n", NS2CH(identifier), (int)[group count]);
      return -1;
    }
    
    oldGroup = [group objectAtIndex: 0];
  }

  if (record) {
    if (isNew) {
      if ([groups count] == groupLimit)
        return -2;

      vxSync_log3(VXSYNC_LOG_INFO, @"groups = %s\n", NS2CH(groups));

      for (id groupRecord in groups) {
        if ([[groupRecord objectForKey: VXKeyPhoneIdentifier] integerValue] != firstFree)
          break;
        firstFree++;
      }

      newGroup = [[record mutableCopy] autorelease];
      [newGroup setObject: [NSNumber numberWithInteger: firstFree] forKey: VXKeyPhoneIdentifier];
      [newGroup setObject: identifier forKey: VXKeyIdentifier];
    } else {
      newGroup = [[oldGroup mutableCopy] autorelease];
      [newGroup addEntriesFromDictionary: record];
    }

    [self setGroupPicturePath: newGroup];

    *recordOut = newGroup;
  }

  if ([[oldGroup objectForKey: VXKeyPicturePath] hasPrefix: @"set_as_pic_id_dir/"] &&
      (!record || ![[oldGroup objectForKey: VXKeyPicturePath] isEqualToString: [newGroup objectForKey: VXKeyPicturePath]]))
    [toDelete addObject: [oldGroup objectForKey: VXKeyPicturePath]];

  [groups filterUsingPredicate: [NSPredicate predicateWithFormat: @"%K != %@", VXKeyIdentifier, identifier]];
  if (record) {
    [groups addObject: newGroup];
    [groups sortUsingFunction: groupIDcompare context: nil];
  }

  return 0;
}

- (void) clearAllGroups {
  for (id group in groups) {
    if ([[group objectForKey: VXKeyPicturePath] hasPrefix: @"set_as_pic_id_dir/"])
      [toDelete addObject: [group objectForKey: VXKeyPicturePath]];
  }
  
  [self setGroups: [NSMutableArray arrayWithCapacity: 30]];
}

- (int) addGroup: (NSDictionary *) record recordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  return [self modifyGroup: record recordOut: recordOut identifier: identifier isNew: YES];
}

- (NSString *) getIdentifierForGroupWithID: (short) groupID {
  NSArray *tmp = [groups filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"%K == %hu", VXKeyPhoneIdentifier, groupID]];
  
  if (1 != [tmp count]) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"count of object matching %K = %hi: %i\n", VXKeyPhoneIdentifier, groupID, (int)[tmp count]);
    return nil;
  }
  
  return [[tmp objectAtIndex: 0] objectForKey: VXKeyIdentifier];
}

- (void) setGroupPicturePath: (NSMutableDictionary *) group {
  NSString *path = nil;
  NSData *pictureData = [group objectForKey: @"image"];
  
  if (pictureData) {
    /* use the crc32 of the image to ensure a unique filename */
    /* newer phones require picture id images be stored into /set_as_pic_id_dir/ */
    path = ![[phone efs] stat: @"set_as_pic_id_dir" to: NULL] ? @"set_as_pic_id_dir/" : @"brew/mod/10888/";
    path = [path stringByAppendingFormat: @"%d.jpg", crc32 ((u_int8_t *)[pictureData bytes], [pictureData length]) + [[group objectForKey: VXKeyPhoneIdentifier] intValue]];

    [group setObject: path forKey: VXKeyPicturePath];
  } 
}

@end
