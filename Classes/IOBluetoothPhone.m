/* (-*- objc -*-)
 * vxSync: IOBluetoothPhone.m
 * (C) 2010-2011 Nathan Hjelm
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

#include <stdlib.h>
#include <stdio.h>

#include <pthread.h>
#include <termios.h>

#include <IOBluetooth/IOBluetooth.h>

#include "IOBluetoothPhone.h"
#define BAUDRATE B115200

static const unsigned int supportedMACs[] = {0x001fe3, 0x0026e2, 0x001f6b, 0x2021a5, 0x002483, 0x0025e5, 0x6cd68a, /* anything past here is a guess */ 0x0022a9, 0x0021fb, 0x001ec7, 0x001c62, 0};

/*
  NSMutableSet *buildDeviceList

  Build a list of paired devices that MIGHT be supported.
*/
static inline NSMutableSet *buildDeviceList (void) {
  NSArray *btdevices = [IOBluetoothDevice pairedDevices];
  NSMutableSet *devices = [NSMutableSet set];
  int i;
  
  for (IOBluetoothDevice *btdevice in btdevices) {
    if ([btdevice getServiceClassMajor] & kBluetoothServiceClassMajorTelephony) {
      const BluetoothDeviceAddress *btaddr = [btdevice getAddress];
      unsigned int vendorID = (btaddr->data[0] << 16) | (btaddr->data[1] << 8) | btaddr->data[2]; 
      
      for (i = 0 ; supportedMACs[i] ; i++) {
        if (supportedMACs[i] == vendorID) {
          vxSync_log3(VXSYNC_LOG_INFO, @"Found possible LG phone device %s\n", [[btdevice getAddressString] UTF8String]);
          [devices addObject: [NSString stringWithFormat:@"Bluetooth::%@", [btdevice getAddressString]]];
        }
      }
    }
  }
  
  return devices;
}

static inline NSSet *bluetoothPhoneProbe () {
  return buildDeviceList ();
}


@implementation IOBluetoothPhone

+ (NSSet *) scanDevices {
  return bluetoothPhoneProbe ();
}

+ (void) startNotifications {
  return; /* not supported -- IOBluetoothDevice is not thread safe! >:( */
}

+ (void) stopNotifications {
  return; /* do nothing */
}

+ (id) phoneWithLocation: (id) locationIn {
  return [[[IOBluetoothPhone alloc] initWithLocation: locationIn] autorelease];
}

@synthesize location, error, openFinished, connectionFinished;
@synthesize dataQueue, queueLock, closeFinished, device;

- (id) initWithLocation: (id) locationIn {
  self = [super init];
  
  [self setLocation: locationIn];
  
  return self;
}

- (void) dealloc {
  [self close];
  [self setLocation: nil];

  [super dealloc];
}

- (void)connectionComplete: (IOBluetoothDevice *) btdevice status: (IOReturn) status {
  vxSync_log3(VXSYNC_LOG_INFO, @"connection to bluetooth device complete with status: %d\n", status);
  [self setError: status];
  [self setConnectionFinished: YES];
}

- (int) open {  
  BluetoothDeviceAddress btAddress;
  IOBluetoothDevice *_device;  
  BluetoothRFCOMMChannelID rfcommChannelID;
  int kReturn;

  if (isOpen)
    return 0;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"opening bluetooth device: %s\n", NS2CH(location));
  
  /* set up the bluetooth device */
  [self setQueueLock: [[[NSLock alloc] init] autorelease]];
  [self setDataQueue: [NSMutableArray array]];
  [self setError: 0];
  [self setCloseFinished: NO];
  [self setOpenFinished: NO];

  IOBluetoothNSStringToDeviceAddress(location, &btAddress);
  
  _device = [IOBluetoothDevice withAddress: &btAddress];
  if (!_device) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not create device.\n");
    [self setError: -1];
    return -1;
  }
  
  [self setConnectionFinished: NO];
  kReturn = [_device openConnection: self withPageTimeout: 0x2000 authenticationRequired: NO];
  if (kIOReturnSuccess != kReturn) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open connection to device. error = %08x\n", kReturn);
    [self setError: kReturn];
    return -1;
  }

  while (!connectionFinished)
    [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate distantFuture]];
  
  if (![_device isConnected] || error) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open connection to device. error = %08x\n", error);
    return -1;
  }

  [self setDevice: _device];

  IOBluetoothSDPUUID *sppServiceUUID = [IOBluetoothSDPUUID uuid16: kBluetoothSDPUUID16ServiceClassSerialPort];
  
  IOBluetoothSDPServiceRecord *sppServiceRecord = [device getServiceRecordForUUID:sppServiceUUID];
  if (nil == sppServiceRecord) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"no SPP service on device.\n");
    [self close];
    return -1;
  }
  
  kReturn = [sppServiceRecord getRFCOMMChannelID: &rfcommChannelID];
  if (kReturn != kIOReturnSuccess) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"no RFCOMM Port on device.\n");
    [self close];
    [self setError: kReturn];
    return -1;
  }

  vxSync_log3(VXSYNC_LOG_INFO, @"RFCOMM port: %i\n", rfcommChannelID);
  
  kReturn = [device openRFCOMMChannelAsync: &commChannel withChannelID: rfcommChannelID delegate: self];
  if (kIOReturnSuccess != kReturn) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open RFCOMM port %i. error = %08x\n", rfcommChannelID, kReturn);
    commChannel = nil;
    [self close];
    [self setError: kReturn];
    return -1;
  }
  
  while (!openFinished)
    [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate distantFuture]];
  
  if (![commChannel isOpen] || error) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open RFCOMM port %i. error = %08x\n", rfcommChannelID, error);
    [self close];
    return -1;
  }
  [commChannel retain];

  [commChannel setSerialParameters: BAUDRATE dataBits: 8 parity: kBluetoothRFCOMMParityTypeNoParity stopBits: 1];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"success.\n");

  isOpen = YES;
  
  return 0;
}

- (int) close {
  if ([commChannel isOpen]) {
    [self setCloseFinished: NO];
    [commChannel closeChannel];
    
    while (!closeFinished)
      [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 10]];
    
    [commChannel release];
    [commChannel release];
    commChannel = nil;
  }
  
  if ([device isConnected])
    [device closeConnection];
  
  [self setDevice: nil];
  [self setQueueLock: nil];
  [self setDataQueue: nil];

  isOpen = NO;

  return 0;
}

- (int) read: (void *) bytes size: (UInt32) count {
  int ret = 0;
  int readCount = 0;
  int tries;

  for (tries = 0 ; tries < 20 && ![dataQueue count] ; tries++)
    /* wait for some data */
    [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 2]];

  while ([dataQueue count]) {
    NSData *data = [dataQueue objectAtIndex: 0];

    ret = (count < [data length]) ? count : [data length];

    [data getBytes: (unsigned char *)bytes + readCount length: ret];

    [dataQueue removeObjectAtIndex: 0];
    
    readCount += ret;
    count     -= ret;
    /* we might want to push the remaining data back on the queue?? */
  }

  return readCount;
}

- (int) write: (void *) bytes size: (UInt32) count {
  int toWrite = count;
  int ret, segmentsize;
  int mtu = [commChannel getMTU];

  do {
    segmentsize = (toWrite > mtu) ? mtu : toWrite;

    ret = [commChannel writeSync: bytes length: segmentsize];
    if (kIOReturnSuccess != ret)
      break;
    
    toWrite -= segmentsize;
    bytes    = (void *)((char *)bytes + segmentsize);
  } while (toWrite);

  return (kIOReturnSuccess == ret) ? count : -1;
}

/* bufferLen should be 2 * len + 6 to handle the worst-case senario */
-(int) write_message: (u_int8_t *) buffer withLength: (size_t) len bufferSize: (size_t) bufferLen {
  int msg_size, ret;
  u_int16_t crc_ccitt;
  
  /* not enough space to buffer the data */
  if (bufferLen - len < 3)
    return -1;
  
  /* messages are appended with a crc16-CCITT checksum */
  crc_ccitt = OSSwapHostToLittleInt16(crc16_ccitt (buffer, len));
  memcpy (buffer + len, &crc_ccitt, 2);
  
  len += 2;
  /* escape all instances of 0x7e and 0x7d within the message */
  msg_size = ppp_escape_inplace (buffer, len, bufferLen);
  
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: buffer length: msg_size], @"writing to phone:\n");
  ret = [self write: buffer size: msg_size];
  
  vxSync_log3(VXSYNC_LOG_DATA, @"write returned: %i\n", ret);
  
  return ret;
}

/* read until a 0x7e is encountered or until buffer space is exhausted */
- (int) read_message: (u_int8_t *) buffer length: (size_t) len {
  int msg_size, ret;
  u_int16_t calc_cksum, msg_cksum;
  NSData *orig;
  
  msg_size = 0;
  
  vxSync_log3(VXSYNC_LOG_DATA, @"reading message of size up to %d to %p\n", len, buffer);
  
  do {
    ret = [self read: &buffer [msg_size] size: len - msg_size];
    
    if (ret < 0) {
      vxSync_log3(VXSYNC_LOG_ERROR, @"error reading from device: code = %i\n", ret);
      return -1;
    }
    
    msg_size += ret;
  } while ((ret > 0) && (msg_size < len) && (buffer[msg_size-1] != 0x7e));
  
  if (msg_size > 2) {
    orig = [NSData dataWithBytes: buffer length: msg_size];
    msg_size = ppp_unescape_inplace (buffer, msg_size) - 2;
  
    vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: buffer length: msg_size], @"read from phone:\n");
  
    /* verify message cksum */
    msg_cksum = OSReadLittleInt16 (buffer, msg_size);
    calc_cksum = crc16_ccitt (buffer, msg_size);
    if (msg_cksum != calc_cksum) {
      vxSync_log3(VXSYNC_LOG_ERROR, @"message checksums do not match: 0x%x <> 0x%x!\n", msg_cksum, calc_cksum);
      vxSync_log3_data(VXSYNC_LOG_ERROR, [NSData dataWithBytes: buffer length: msg_size], @"message data:\n");
      vxSync_log3_data(VXSYNC_LOG_ERROR, orig, @"original data:\n");
      errno = EIO;
    
      return -1;
    }
  }

  return msg_size;
}

@end

@implementation IOBluetoothPhone (IOBluetoothRFCOMMChannelDelegate)
- (void) rfcommChannelData:(IOBluetoothRFCOMMChannel*)rfcommChannel data:(void *)dataPointer length:(size_t)dataLength {  
  [dataQueue addObject: [NSData dataWithBytes: dataPointer length: dataLength]];
}

- (void) rfcommChannelOpenComplete: (IOBluetoothRFCOMMChannel*) rfcommChannel status: (IOReturn) commerror {
  vxSync_log3(VXSYNC_LOG_INFO, @"rfcommChannel open: error = %08x\n", commerror);
  if (commerror)
    [self setError: commerror];
  [self setOpenFinished: YES];
}

- (void) rfcommChannelClosed: (IOBluetoothRFCOMMChannel*) rfcommChannel {
  vxSync_log3(VXSYNC_LOG_INFO, @"rfcommChannel closed\n");
  [self setCloseFinished: YES];
}
@end

#if defined(__test_bluetooth__)

mach_port_t masterPort;

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  struct notification_data data;
  pthread_t thread;
  void *returnv;
  unsigned char buffer[2048];
  int i, ret;
  IOBluetoothPhone *phone;

#if 0
  for (i = 0 ; i < 3 ; i++) {
    phone = [IOBluetoothPhone newWithLocation: @"00-26-e2-f3-5a-58"];
    [phone open];
    buffer[0]= 0xf1;
    buffer[1] = 0x0a;
    [phone write_message: buffer withLength: 2 bufferSize: 2048];
    ret = [phone read_message: buffer length: 2048];
    pretty_print_block(buffer, ret);
    usleep(100000);
    [phone close];
    
    
    usleep(1000000);
    
    
    phone = [IOBluetoothPhone newWithLocation: @"00-26-e2-5e-af-85"];
    [phone open];
    buffer[0]= 0xf1;
    buffer[1] = 0x0a;
    [phone write_message: buffer withLength: 2 bufferSize: 2048];
    ret = [phone read_message: buffer length: 2048];
    pretty_print_block(buffer, ret);
    usleep(100000);
    [phone close];
    usleep(1000000);
  }
#else
  data.lock = [[[NSLock alloc] init] autorelease];
  data.list = [NSMutableArray array];

  if (1) {
    bluetoothPhoneProbe((void *)&data);
    printf ("Found phones: %s\n", [[data.list description] UTF8String]);
  } else {
    pthread_create (&thread, NULL, bluetoothPhoneProbe, (void *)&data);
    pthread_join (thread, &returnv);
  }
#endif
  
  [releasePool release];
  
  return 0;
}
#endif
