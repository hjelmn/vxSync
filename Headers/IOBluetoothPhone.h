/* (-*- objc -*-)
 * vxSync: IOBluetoothPhone.h
 * Copyright (C) 2010 Nathan Hjelm
 * v0.6.3
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
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
