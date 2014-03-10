/* (-*- objc -*-)
 * vxSync: IOBluetoothPhone.h
 * Copyright (C) 2010 Nathan Hjelm
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

#if !defined(IOBLUETOOTHPHONE_H)
#define IOBLUETOOTHPHONE_H

#include "IOUSBPhone.h"
#include "VXSync.h"

#include <termios.h>
#include <pthread.h>

#include <IOBluetooth/IOBluetooth.h>

@interface IOBluetoothPhone : NSObject <PhoneDevice> {
@private
  id location;
  
  NSMutableArray *dataQueue;
  NSLock *queueLock;
  IOBluetoothDevice *device;
  IOBluetoothRFCOMMChannel *commChannel;
  int error;
  BOOL openFinished, closeFinished, connectionFinished;
  BOOL isOpen;
}

@property BOOL openFinished;
@property BOOL closeFinished;
@property BOOL connectionFinished;
@property int error;
@property (retain) NSMutableArray *dataQueue;
@property (retain) NSLock *queueLock;
@property (retain) IOBluetoothDevice *device;


- (void)connectionComplete: (IOBluetoothDevice *) btdevice status: (IOReturn) status;

@end

@interface IOBluetoothPhone (IOBluetoothRFCOMMChannelDelegate)
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel*)rfcommChannel data:(void *)dataPointer length:(size_t)dataLength;
- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel*)rfcommChannel status:(IOReturn)error;
- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel*)rfcommChannel;
@end

#endif
