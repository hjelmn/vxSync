/* (-*- objc -*-)
 * vxSync: IOUSBPhone.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.3
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

#if !defined(IOUSBPHONE_H)
#define IOUSBPHONE_H

#include "VXSync.h"

#include <IOKit/IOCFBundle.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/IOCFPlugIn.h>

typedef IOUSBDeviceInterface300 usb_device_t;
typedef IOUSBInterfaceInterface300 usb_interface_t;

#define DeviceInterfaceID kIOUSBDeviceInterfaceID245

@interface IOUSBPhone : NSObject <PhoneDevice> {
@private
  usb_device_t **usbDevice;
  usb_interface_t **usbInterface;
  id location;
  UInt8 readPipe, writePipe;
  BOOL deviceIsOpen;
}
@property (retain) id location;
@end

#endif
