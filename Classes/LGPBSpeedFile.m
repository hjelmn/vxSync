/* (-*- objc -*-)
 * vxSync: LGPBSpeedFile.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
 *
 * Changes:
 *  - 0.3.1 - Move LGException class into a seperate file. Bug fixes and code cleanup
 *  - 0.3.0 - Cleaner code. Support for commitChanges. Better support for all day events. Multiple calendars support.
 *  - 0.2.3 - Bug fixes
 *  - 0.2.0 - Initial release
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "LGPBSpeedFile.h"


@implementation LGPBEntryFile (Speeds)

- (int) readSpeeds {
  int speed_fd, i;
  unsigned char speed_data[3 * kMaxSpeeds];
  
  [self setSpeeds: [NSMutableArray arrayWithCapacity: kMaxSpeeds]];
  
  speed_fd = [[phone efs] open: VXPBSpeedPath withFlags: O_RDONLY];
  memset (speed_data, 0xff, 3 * kMaxSpeeds);
  if (speed_fd > -1) {
    [[phone efs] read: speed_fd to: speed_data count: 3 * kMaxSpeeds];
    [[phone efs] close: speed_fd];
    
    for (i = 0 ; i < kMaxSpeeds ; i++) {
      /* clean out bad speed data */
      if (speed_data[3 * i + 2] == 0 || speed_data[3 * i + 2] > 5 || OSReadLittleInt16 (speed_data, 3 * i) >= contactLimit) {
        OSWriteLittleInt16 (speed_data, 3 * i, 0xffff);
        speed_data[3 * i + 2] = 0xff;
      }
      
      [speeds addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithUnsignedInt: OSReadLittleInt16 (speed_data, 3 * i)], VXKeyValue,
                           [NSNumber numberWithUnsignedInt: speed_data[3 * i + 2]], VXKeyType,
                           [NSNumber numberWithUnsignedInt: i], VXKeyIndex,
                           nil]];
    }

    return 0;
  }
  
  return -1;
}

- (int) commitSpeeds {
  unsigned char speed_data[3 * kMaxSpeeds];
  int ret;
  
  /* write speed dials */
  vxSync_log3(VXSYNC_LOG_DEBUG, @"Writing speed dials: %s", NS2CH(speeds));
  for (id speed in speeds) {
    int speed_index = [[speed objectForKey: VXKeyIndex] intValue];
    
    OSWriteLittleInt16 (speed_data, 3 * speed_index, [[speed objectForKey: VXKeyValue] unsignedIntValue]);
    speed_data[3 * speed_index + 2] = [[speed objectForKey: VXKeyType] unsignedCharValue];
  }
  
  ret = [[phone efs] write_file_data: [NSData dataWithBytes: speed_data length: 3 * kMaxSpeeds] to: VXPBSpeedPath];
  if (ret <= 0)
    vxSync_log3(VXSYNC_LOG_WARNING, @"could not open phone:%s for writing", NS2CH(VXPBSpeedPath));
  
  return 0;
}

- (NSArray *) speedsForContact: (int) contactIndex {
  return [speeds filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"%K == %i", VXKeyValue, contactIndex]];
}

- (int) setSpeedDial: (int) speedNumber withContact: (int) contactIndex numberType: (int) numberType {
  [speeds replaceObjectAtIndex: speedNumber withObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                                         [NSNumber numberWithUnsignedInt: contactIndex], VXKeyValue,
                                                         [NSNumber numberWithUnsignedInt: numberType],   VXKeyType,
                                                         [NSNumber numberWithUnsignedInt: speedNumber],  VXKeyIndex,
                                                         nil]];
  
  return 0;
}

@end
