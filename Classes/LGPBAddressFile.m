/* (-*- objc -*-)
 * vxSync: LGPBAddressFile.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.4
 *
 * Changes:
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

#include "LGPBAddressFile.h"


@implementation LGPBEntryFile (StreetAddress)

/* there are two address formats: enV touch, chocolate touch . the formats differ by one extra byte at the end of the chocolate touch structure */
- (int) getStreetAddress: (int) addressIndex storeIn: (NSMutableDictionary *) dict {
  unsigned char addressBytes[addressEntryLength];
  struct lg_address *addressData = (struct lg_address *) addressBytes;
  NSMutableDictionary *newAddress = [NSMutableDictionary dictionary];
  int fd;
  
  if (addressOffset < 0 || addressIndex > contactLimit)
    return -1;
  
  fd = [[phone efs] open: VXPBAddressPath withFlags: O_RDONLY];
  
  if (fd < -1)
    return -1;
  
  [[phone efs] lseek: fd toOffset: addressIndex * addressEntryLength whence: SEEK_SET];
  [[phone efs] read: fd to: addressBytes count: addressEntryLength];

  _inUseFlag[addressIndex] |= 0x02;
  
  [newAddress setObject: EntityAddress forKey: RecordEntityName];
  if (strlen (addressData->street))
    [newAddress setObject: stringFromBuffer((unsigned char *)addressData->street, 52, NSISOLatin1StringEncoding) forKey: @"street"];
  if (strlen (addressData->city))
    [newAddress setObject: stringFromBuffer((unsigned char *)addressData->city, 52, NSISOLatin1StringEncoding) forKey: @"city"];
  if (strlen (addressData->country))
    [newAddress setObject: stringFromBuffer((unsigned char *)addressData->country, 52, NSISOLatin1StringEncoding) forKey: @"country"];
  if (strlen (addressData->zip))
    [newAddress setObject: stringFromBuffer((unsigned char *)addressData->zip, 13, NSISOLatin1StringEncoding) forKey: @"postal code"];
  if (strlen (addressData->state))
    [newAddress setObject: stringFromBuffer((unsigned char *)addressData->state, 52, NSISOLatin1StringEncoding) forKey: @"state"];
  [newAddress setObject: [NSNumber numberWithUnsignedInt: addressIndex] forKey: VXKeyIndex];
  
  [dict setObject: [[newAddress copy] autorelease] forKey: @"street address"];
  
  [[phone efs] close: fd];
  
  return 0;
}

- (int) commitStreetAddresses {
  int i, address_fd;
  struct stat statinfo;
  unsigned char addressBytes[addressEntryLength];
  struct lg_address *addressData = (struct lg_address *) addressBytes;
  
  if (addressOffset == -1)
    return -1;
  
  memset (addressBytes, 0xff, addressEntryLength);
  if ([[phone efs] stat: VXPBAddressPath to: &statinfo] < 0) {
    address_fd = [[phone efs] open: VXPBAddressPath withFlags: O_WRONLY | O_CREAT, 0600];
    if (address_fd > -1)
      for (i = 0 ; i < contactLimit ; i++)
        [[phone efs] write: address_fd from: addressBytes count: addressEntryLength];
  } else
    address_fd = [[phone efs] open: VXPBAddressPath withFlags: O_RDWR];
  
  for (i = 0 ; i < contactLimit ; i++) {
    if (_inUseFlag[i] & 0x01) {
      NSDictionary *addressDict = [[_contacts objectAtIndex: i] objectForKey: @"street address"];

      if (addressDict) {
        int addressIndex = [[addressDict objectForKey: VXKeyIndex] intValue];
        
        if (_inUseFlag[addressIndex] & 0x10) {
          [[phone efs] lseek: address_fd toOffset: addressIndex * addressEntryLength whence: SEEK_SET];
          
          memset (addressData, 0, addressEntryLength);
          
          strcpy (addressData->entry_tag, "<PA>");
          addressData->address_index = OSSwapHostToLittleInt16 (addressIndex);
          addressData->entry_index   = OSSwapHostToLittleInt16 (i);
          [[addressDict objectForKey: @"street"] getCString: addressData->street maxLength: sizeof (addressData->street) encoding: NSISOLatin1StringEncoding];
          [[addressDict objectForKey: @"postal code"] getCString: addressData->zip maxLength: sizeof (addressData->zip) encoding: NSISOLatin1StringEncoding];
          [[addressDict objectForKey: @"city"] getCString: addressData->city maxLength: sizeof (addressData->city) encoding: NSISOLatin1StringEncoding];
          [[addressDict objectForKey: @"state"] getCString: addressData->state maxLength: sizeof (addressData->state) encoding: NSISOLatin1StringEncoding];
          [[addressDict objectForKey: @"country"] getCString: addressData->country - (addressEntryLength == 256) maxLength: sizeof (addressData->country) encoding: NSISOLatin1StringEncoding];
          strcpy (addressData->exit_tag + (addressEntryLength == 256), "</PA>");
          
          [[phone efs] write: address_fd from: (unsigned char *) addressData count: addressEntryLength];
        }
        
        /* unset the address dirty flag */
        _inUseFlag[addressIndex] &= 0xffef;
      }
    }
  }
  
  [[phone efs] close: address_fd];
  
  return 0;
}

@end
