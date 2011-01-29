/* (-*- objc -*-)
 * vxSync: IOUSBPhone.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.3
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
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
