/* (-*- objc -*-)
 * vxSync: LGPhonebook.m
 * (C) 2009-2010 Nathan Hjelm
 * v0.6.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include <stdlib.h>
#include <stdio.h>

#include <pthread.h>

#include "IOUSBPhone.h"

static usb_device_t **getNextDevice (io_iterator_t deviceIterator, UInt32 *locationp);

static pthread_t    workerThread = NULL;
static CFRunLoopRef threadRunloop = NULL;

static char *kErrorString (int result) {
  switch (result) {
  case kIOReturnSuccess:
    return "no error";
  case kIOReturnNotOpen:
    return "device not opened for exclusive access";
  case kIOReturnNoDevice:
    return "no connection to an IOService";
  case kIOUSBNoAsyncPortErr:
    return "no async port has been opened for interface";
  case kIOReturnExclusiveAccess:
    return "another process has device opened for exclusive access";
  case kIOUSBPipeStalled:
    return "pipe is stalled";
  case kIOReturnError:
    return "could not establish a connection to the Darwin kernel";
  case kIOUSBTransactionTimeout:
    return "transaction timed out";
  case kIOReturnBadArgument:
    return "invalid argument";
  case kIOReturnAborted:
    return "transaction aborted";
  case kIOReturnNotResponding:
    return "device not responding";
  default:
    return "unknown error";
  }
}

static void readRegistyValue (io_service_t reg, CFStringRef value, CFNumberType type, void *store) {
  CFTypeRef cfValue = IORegistryEntryCreateCFProperty (reg, value, kCFAllocatorDefault, 0);
  if (cfValue) {
    CFNumberGetValue(cfValue, type, store);
    CFRelease (cfValue);
  }
}

void USBDeviceUnplug (void *ptr, io_iterator_t iterator) {
  long long locationID;
  long idVendor, idProduct;
  io_service_t device;

  while ((device = IOIteratorNext (iterator)) != 0) {
    /* get the location, vendor, and device IDs from the i/o registry */
    readRegistyValue(device, CFSTR(kUSBDevicePropertyLocationID), kCFNumberLongLongType, &locationID);
    readRegistyValue(device, CFSTR("idVendor"), kCFNumberLongType, &idVendor);
    readRegistyValue(device, CFSTR("idProduct"), kCFNumberLongType, &idProduct);
    
    vxSync_log3(VXSYNC_LOG_INFO, @"USB device @ USB::%u unplugged (vid = 0x%04x, pid = 0x%04x)\n", locationID, idVendor, idProduct);
    if (idVendor == 0x1004 && idProduct == 0x6000)
      [[NSNotificationCenter defaultCenter] postNotificationName: @"USBDeviceUnplug" object: [NSString stringWithFormat: @"USB::%u", (UInt32)locationID]];

    IOObjectRelease (device);
  }
}

void USBDevicePlug (void *ptr, io_iterator_t iterator) {
  usb_device_t         **device;
  UInt32 location;
  UInt16               idProduct, idVendor;
  NSMutableSet *devices = (NSMutableSet *)ptr;

  while (device = getNextDevice (iterator, &location)) {
    (*device)->GetDeviceProduct (device, &idProduct);
    (*device)->GetDeviceVendor (device, &idVendor);

    vxSync_log3(VXSYNC_LOG_INFO, @"USB device @ USB::%u plugged in (vid = 0x%04x, pid = 0x%04x)\n", location, idVendor, idProduct);
    if (idVendor == 0x1004 && idProduct == 0x6000) {
      if (devices)
        [devices addObject: [NSString stringWithFormat: @"USB::%u", location]];

      [[NSNotificationCenter defaultCenter] postNotificationName: @"USBDevicePlug" object: [NSString stringWithFormat: @"USB::%u", (UInt32)location]];
    }

    (*device)->Release (device);
  }
}

void clearIterator (io_iterator_t iter) {
  io_service_t device;

  while ((device = IOIteratorNext (iter)) != 0)
    IOObjectRelease (device);
}

static void *USBEventThread (void *arg0) {
  /* each thread needs its own autorelease pool */
  NSAutoreleasePool     *releasePool = [[NSAutoreleasePool alloc] init];
  CFRunLoopSourceRef    notification_cfsource;
  IONotificationPortRef notification_port;
  io_iterator_t         unplug_iterator, plug_iterator;
  IOReturn              kresult;

  CFRetain (CFRunLoopGetCurrent ());

  /* add the notification port to the run loop */
  notification_port     = IONotificationPortCreate (IO_OBJECT_NULL);
  notification_cfsource = IONotificationPortGetRunLoopSource (notification_port);
  CFRunLoopAddSource(CFRunLoopGetCurrent (), notification_cfsource, kCFRunLoopDefaultMode);

  /* create notifications for removed devices */
  kresult = IOServiceAddMatchingNotification (notification_port, kIOTerminatedNotification,
                                              IOServiceMatching(kIOUSBDeviceClassName),
                                              (IOServiceMatchingCallback)USBDeviceUnplug,
                                              arg0, &unplug_iterator);

  if (kresult != kIOReturnSuccess)
    pthread_exit (0);

  kresult = IOServiceAddMatchingNotification (notification_port, kIOFirstMatchNotification,
                                              IOServiceMatching(kIOUSBDeviceClassName),
                                              (IOServiceMatchingCallback)USBDevicePlug,
                                              arg0, &plug_iterator);

  if (kresult != kIOReturnSuccess)
    pthread_exit (0);

  /* arm notifiers */
  clearIterator (plug_iterator);
  clearIterator (unplug_iterator);

  threadRunloop = CFRunLoopGetCurrent ();

  /* run the runloop */
  CFRunLoopRun();

  /* delete notification port */
  CFRunLoopSourceInvalidate (notification_cfsource);
  IONotificationPortDestroy (notification_port);

  CFRelease (CFRunLoopGetCurrent ());

  threadRunloop = NULL;

  [releasePool release];

  pthread_exit (0);
}

static int setupDeviceIterator (io_iterator_t *deviceIterator) {
  return IOServiceGetMatchingServices (IO_OBJECT_NULL, IOServiceMatching(kIOUSBDeviceClassName), deviceIterator);
}

static usb_device_t **getNextDevice (io_iterator_t deviceIterator, UInt32 *locationp) {
  IOCFPlugInInterface **plugInInterface = NULL;
  usb_device_t **device;
  io_service_t usbDevice;
  long result;
  SInt32 score;

  if (!IOIteratorIsValid (deviceIterator) || !(usbDevice = IOIteratorNext(deviceIterator)))
    return NULL;
  
  result = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID,
                                             kIOCFPlugInInterfaceID, &plugInInterface,
                                             &score);
  (void)IOObjectRelease(usbDevice);
  if (result || !plugInInterface) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not set up plugin for service\n");

    return NULL;
  }

  (void)(*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(DeviceInterfaceID),
                                           (LPVOID)&device);

  (*plugInInterface)->Stop(plugInInterface);
  IODestroyPlugInInterface (plugInInterface);
  
  (*device)->GetLocationID(device, locationp);

  return device;
}

@interface IOUSBPhone (hidden)
+ (int) ppp_escape_inplace: (u_int8_t *) msg length: (size_t) len bufferSize: (size_t) buffer_len;
+ (int) ppp_unescape_inplace: (u_int8_t *) msg length: (size_t) len;
@end

@implementation IOUSBPhone
+ (NSSet *) scanDevices {
  io_iterator_t        deviceIterator;
  IOReturn             kresult;
  NSMutableSet *devices = [NSMutableSet set];
  
  kresult = setupDeviceIterator (&deviceIterator);
  if (kIOReturnSuccess == kresult) {
    USBDevicePlug ((void *)devices, deviceIterator);

    IOObjectRelease(deviceIterator);
  }

  return devices;
}

+ (void) startNotifications {
  if (!workerThread)
    pthread_create (&workerThread, NULL, USBEventThread, NULL);
}

+ (void) stopNotifications {
  void *returnVal;

  if (threadRunloop)
    CFRunLoopStop (threadRunloop);

  pthread_join (workerThread, &returnVal);
}

+ (id) phoneWithLocation: (id) locationIn {
  return [[[IOUSBPhone alloc] initWithLocation: locationIn] autorelease];
}

- (id) initWithLocation: (id) locationIn {
  io_iterator_t        deviceIterator;
  UInt32 deviceLocation;
  IOReturn kresult;
  UInt32 intLocation = (UInt32)[locationIn longLongValue];

  self = [super init];
  [self setLocation: locationIn];

  usbDevice    = nil;
  usbInterface = nil;

  /* XXX -- register to recieve device removal notifications here */
  //  [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(someDeviceLeft) name: @"deviceLeft" object: self];

  /* XXX -- find the device */
  kresult = setupDeviceIterator (&deviceIterator);
  if (kresult != kIOReturnSuccess)
    return nil;

  while (usbDevice = getNextDevice (deviceIterator, &deviceLocation))
    if (intLocation == deviceLocation)
      break;
  
  if (!usbDevice)
    return nil;
  
  deviceIsOpen = NO;
  
  IOObjectRelease(deviceIterator);

  return self;
}

@synthesize location;

- (void) dealloc {
  [self close];
  if (usbDevice)
    (*usbDevice)->Release (usbDevice);
  
  usbDevice = NULL;
  usbInterface = NULL;
  [self setLocation: nil];

  [super dealloc];
}

- (int) open {
  IOUSBFindInterfaceRequest request;
  UInt8 direction, dontcare, numEndpoints, number;
  UInt16 dontcare16;
  IOReturn                  kresult;
  io_iterator_t             interface_iterator;
  io_service_t              interfaceService;
  SInt32                    score;
  IOCFPlugInInterface       **plugInInterface = NULL;
  
  if (!usbDevice)
    return -1;
  
  kresult = (*usbDevice)->USBDeviceOpen (usbDevice);
  if (kresult == kIOReturnSuccess) {
    deviceIsOpen = YES;

    (void) (*usbDevice)->USBDeviceSuspend (usbDevice, 0); /* unsuspend the device if necessary */
    (void) (*usbDevice)->SetConfiguration (usbDevice, 0);
  }
  
  usbInterface = IO_OBJECT_NULL;

  /* Setup the Interface Request */
  request.bInterfaceClass    = 255;
  request.bInterfaceSubClass = 255;
  request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
  request.bAlternateSetting  = kIOUSBFindInterfaceDontCare;

  kresult = (*usbDevice)->CreateInterfaceIterator(usbDevice, &request, &interface_iterator);
  if (kresult)
    return kresult;

  /* just grab the first vendor specific interface */
  interfaceService = IOIteratorNext(interface_iterator);

  /* done with the interface iterator */
  IOObjectRelease(interface_iterator);
  /* make sure we have an interface */
  if (!interfaceService && deviceIsOpen) {
    u_int8_t nConfig, new_config;     /* Index of configuration to use */
    IOUSBConfigurationDescriptorPtr configDesc; /* to describe which configuration to select */
    /* Only a composite class device with no vendor-specific driver will
     be configured. Otherwise, we need to do it ourselves, or there
     will be no interfaces for the device. */

    vxSync_log3(VXSYNC_LOG_WARNING, @"no interface found. configuring device..\n");
    
    kresult = (*usbDevice)->GetNumberOfConfigurations (usbDevice, &nConfig);
    if (kresult != kIOReturnSuccess)
      return -1;

    if (nConfig < 1)
      return -1;
    
    /* Always use the first configuration */
    kresult = (*usbDevice)->GetConfigurationDescriptorPtr (usbDevice, 0, &configDesc);
    if (kresult != kIOReturnSuccess)
      new_config = 1;
    else
      new_config = configDesc->bConfigurationValue;

    /* set the configuration */
    kresult = (*usbDevice)->SetConfiguration (usbDevice, new_config);
    if (kresult != kIOReturnSuccess)
      return -1;

    kresult = (*usbDevice)->CreateInterfaceIterator(usbDevice, &request, &interface_iterator);
    if (kresult)
      return -1;
    
    /* just grab the first vendor specific interface */
    interfaceService = IOIteratorNext(interface_iterator);
    
    /* done with the interface iterator */
    IOObjectRelease(interface_iterator);
  }
  
  if (!interfaceService) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not find phone's diagnostic interface\n");
    return -1;
  }

  /* get an interface to the device's interface */
  kresult = IOCreatePlugInInterfaceForService (interfaceService, kIOUSBInterfaceUserClientTypeID,
                                               kIOCFPlugInInterfaceID, &plugInInterface, &score);

  /* ignore release error */
  (void)IOObjectRelease (interfaceService);

  if (kresult || !plugInInterface) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not create plug-in interface for service\n");
    return -1;
  }

  /* Do the actual claim */
  kresult = (*plugInInterface)->QueryInterface(plugInInterface,
                                               CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                                               (LPVOID)&usbInterface);
  /* We no longer need the intermediate plug-in */
  (*plugInInterface)->Release(plugInInterface);
  if (kresult || !usbInterface) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"QueryInterface failed\n");
    return -1;
  }

  /* claim the interface */
  kresult = (*usbInterface)->USBInterfaceOpen(usbInterface);
  if (kresult) {
    (*usbInterface)->Release (usbInterface);
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open interface\n");
    usbInterface = nil;
    return -1;
  }

  (*usbInterface)->GetNumEndpoints (usbInterface, &numEndpoints);
  if (2 != numEndpoints) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"USB interface does not have the correct number of endpoints: %s (expected 2)\n", numEndpoints);
    [self close];
    return -1;
  }

  (*usbInterface)->GetPipeProperties (usbInterface, 1, &direction, &number, &dontcare, &dontcare16, &dontcare);
  if (direction == kUSBOut) {
    readPipe = 2;
    writePipe = 1;
  } else {
    readPipe = 1;
    writePipe = 2;
  }
  
  (*usbInterface)->ClearPipeStallBothEnds (usbInterface, readPipe);
  (*usbInterface)->ClearPipeStallBothEnds (usbInterface, writePipe);
  
  vxSync_log3(VXSYNC_LOG_INFO, @"USB debug interface found: %p readPipe: %02x writePipe: %02x\n", (void *)usbInterface, readPipe, writePipe);

  return 0;
}

- (int) close {
  if (usbInterface) {
    (void)(*usbInterface)->USBInterfaceClose (usbInterface);
    (*usbInterface)->Release (usbInterface);
    usbInterface = IO_OBJECT_NULL;
  }
  
  if (usbDevice && deviceIsOpen)
    (*usbDevice)->USBDeviceClose (usbDevice);

  return 0;
}

- (int) read: (void *) bytes size: (UInt32) count {
  int kresult;

  if (!usbInterface)
    return -1;

  kresult = (*usbInterface)->ReadPipeTO (usbInterface, readPipe, bytes, &count, 1000, 6000);
  if (kIOReturnOverrun == kresult) {
    (*usbInterface)->ClearPipeStallBothEnds (usbInterface, readPipe);
    kresult = (*usbInterface)->ReadPipeTO (usbInterface, readPipe, bytes, &count, 1000, 6000);
  }

  if (kresult)
    return kresult;

  return count;
}

- (int) write: (void *) bytes size: (UInt32) count {
  int kresult;

  if (!usbInterface)
    return -1;

  kresult = (*usbInterface)->WritePipeTO (usbInterface, writePipe, bytes, count, 1000, 6000);
  if (kIOReturnOverrun == kresult) {
    (*usbInterface)->ClearPipeStallBothEnds (usbInterface, writePipe);
    kresult = (*usbInterface)->WritePipeTO (usbInterface, writePipe, bytes, count, 1000, 6000);
  }

  if (kresult)
    return kresult;

  return count;
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
  
  msg_size = ppp_unescape_inplace (buffer, msg_size) - 2;
  
  vxSync_log3_data(VXSYNC_LOG_DATA, [NSData dataWithBytes: buffer length: msg_size], @"read from phone:\n");
  
  /* verify message cksum */
  msg_cksum = OSReadLittleInt16 (buffer, msg_size);
  calc_cksum = crc16_ccitt (buffer, msg_size);
  if (msg_cksum != calc_cksum) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"message checksums do not match: 0x%x <> 0x%x!\n", msg_cksum, calc_cksum);
    errno = EIO;
    
    return -1;
  }
  
  errno = 0;
  return msg_size;
}

@end

#if 0
#include "cksum.h"
#include "hexdump.c"
#warn "USB test program"

/* test program */
int main (void) {  
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  IOReturn kresult;
  struct notification_data data;
  void *retVal;
  IOUSBPhone *phone;
  char msg[20] = {0x01, };
  u_int16_t crc;

  data.lock  = [[NSLock alloc] init];
  data.list = [NSMutableArray array];

  /* Create the master port for talking to IOKit */
  kresult = IOMasterPort (MACH_PORT_NULL, &masterPort);

  if (kresult != kIOReturnSuccess || !masterPort)
    return -1;

  [IOUSBPhone scanDevices: &data];
  [IOUSBPhone startNotifications: &data];

  crc = crc16_ccitt (msg, 1);
  memmove (msg + 1, &crc, 2);

  phone = [IOUSBPhone newWithLocation: 605028352];
  [phone open];
  [phone write: msg count: 3];
  printf ("Read %i bytes\n", [phone read: msg count: 20]);
  pretty_print_block (msg, 20);
  [phone close];

  pthread_join (workerThread, &retVal);

  mach_port_deallocate(mach_task_self(), masterPort);

  [releasePool release];

  return 0;
}
#endif
