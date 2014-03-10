/* (-*- objc -*-)
 * vxSync: LGPBEntryFile.m
 * (C) 2009-2010 Nathan Hjelm
 * v0.6.2
 *
 * Changes:
 *  - 0.6.1 - Manage picture IDs better.
 *  - 0.6.0 - Group picture IDs
 *  - 0.3.1 - Move LGException class into a seperate file. Bug fixes and code cleanup
 *  - 0.3.0 - Cleaner code. Support for commitChanges. Better support for all day events. Multiple calendars support.
 *  - 0.2.3 - Bug fixes
 *  - 0.2.0 - Initial release
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "VXSync.h"
#include "vxPhone.h"

@interface LGPBTestDump : NSObject {
@private
  vxPhone *phone;
  NSMutableData *buffer;
  char *bytes;
}

@property (retain) vxPhone *phone;
@property (retain) NSMutableData *buffer;

+ (id) newWithPhone: (vxPhone *) phoneIn;
- (id) initWithPhone: (vxPhone *) phoneIn;

- (void) printData;
- (void) printFileTest;
- (void) printProtocolTest;
@end

@implementation LGPBTestDump
+ (id) newWithPhone: (vxPhone *) phoneIn {
  return [[[LGPBTestDump alloc] initWithPhone: phoneIn] autorelease];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];
  if (!self || !phoneIn)
    return nil;

  [self setPhone: phoneIn];
  [self setBuffer: [NSMutableData dataWithLength: 8192]];

  bytes = [buffer mutableBytes];

  /* set up internal values based on file format */
  [self printData];
  
  return self;
}

- (void) printData {
  NSData *groupData;
  NSString *error;

  /* print group data */
  groupData = [[phone efs] get_file_data_from: VXPBGroupPath errorOut: &error];
  if (groupData) {
    fprintf (stderr, "File data from %s\n", [VXPBGroupPath UTF8String]);
    pretty_print_block ((unsigned char *)[groupData bytes], [groupData length]);
  } else
    fprintf (stderr, "Could not read data from %s: %s\n", [VXPBGroupPath UTF8String], [error UTF8String]);


  /* print memo data */
  groupData = [[phone efs] get_file_data_from: VXMemoPath errorOut: &error];
  if (groupData) {
    fprintf (stderr, "File data from %s\n", [VXMemoPath UTF8String]);
    pretty_print_block ((unsigned char *)[groupData bytes], [groupData length]);
  } else
    fprintf (stderr, "Could not read data from %s: %s\n", [VXPBGroupPath UTF8String], [error UTF8String]);

  [self printProtocolTest];
  [self printFileTest];
}

- (void) printFileTest {
  int fd, i, j, apparentLength;
  struct stat statinfo;
  DIR *foo;
  struct dirent *ent;

  foo = [[phone efs] opendir: @"/pim"];
  while (ent = [[phone efs] readdir: foo]) {
    [[phone efs] stat: [@"/pim" stringByAppendingFormat: @"/%s", ent->d_name] to: &statinfo];
    fprintf (stderr, "/pim/%s: size = %d\n", ent->d_name, (int)statinfo.st_size);
  }

  [[phone efs] closedir: foo];


  foo = [[phone efs] opendir: @"/sch"];
  while (ent = [[phone efs] readdir: foo]) {
    [[phone efs] stat: [@"/sch" stringByAppendingFormat: @"/%s", ent->d_name] to: &statinfo];
    fprintf (stderr, "/sch/%s: size = %d\n", ent->d_name, (int)statinfo.st_size);
  }

  [[phone efs] closedir: foo];

  fd = [[phone efs] open: VXPBEntryPath withFlags: O_RDONLY];
  if (-1 == fd)
    return;

  [[phone efs] lseek: fd toOffset: -256 whence: SEEK_END];
  [[phone efs] read: fd to: bytes count: 256];
  if (strncmp (bytes, "<HPE>", 5) == 0)
    apparentLength = 256;
  else
    apparentLength = 512;

  if (apparentLength == 512) {
    [[phone efs] lseek: fd toOffset: -512 whence: SEEK_END];
    [[phone efs] read: fd to: bytes count: 512];
  }

  fprintf (stderr, "Best guess at record length = %i\n", apparentLength);
  fprintf (stderr, "HPE entry\n");
  pretty_print_block (bytes, apparentLength);

  [[phone efs] lseek: fd toOffset: 0 whence: SEEK_SET];

  BOOL found = NO;

  for (i = 0 ; i < 1000 && !found ; i ++) {
    [[phone efs] read: fd to: bytes count: apparentLength];

    for (j = 0 ; j < apparentLength - 24 ; j++) {
      NSString *utf16str = [stringFromBuffer (bytes + j, 22, VXUTF16LEStringEncoding) lowercaseString];
      NSString *utf8str  = [stringFromBuffer (bytes + j, 11, NSISOLatin1StringEncoding) lowercaseString];

      if (isprint (bytes[j]) && ([utf16str hasPrefix: @"vxsync"] || [utf8str hasPrefix: @"vxsync"])) {
	fprintf (stderr, "Possible test contact file at file index: %d\n", i);
	pretty_print_block (bytes, apparentLength);
	found = YES;
      }
    }
  }
  
  [[phone efs] close: fd];
}

- (void) dealloc {
  [self setPhone: nil];
  [self setBuffer: nil];
  
  [super dealloc];
}

- (void) printProtocolTest {
  int i, entryIndex;
  BOOL found = NO;
  int byte, bit, command;

  for (command = 0xff ; command <= 0xff ; ++command) {
    memset  (bytes, 0, 1024);
    bytes[0] = command;
    bytes[1] = 2;
    bytes[2] = 1;
    bytes[10] = 1;
    int ret = [[phone efs] send_recv_message: bytes sendLength: 10 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
    if (bytes[1] != 0x53) {
      fprintf (stderr, "Response from command %d:\n", command);
      pretty_print_block (bytes, ret);
    }
  }

  for (entryIndex = 0 ; entryIndex < 000 && !found ; entryIndex++) {
    memset (bytes, 0, 1024);
    bytes[0] = 0xf1;
    bytes[1] = 0x29;
    OSWriteLittleInt16 (bytes, 2, entryIndex);

    int ret = [[phone efs] send_recv_message: bytes sendLength: 10 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
    vxSync_log3_data (VXSYNC_LOG_DATA, [NSData dataWithBytes: bytes length: ret], @"phonebook data for contact %i:\n", entryIndex);

    for (i = 0 ; i < ret - 24 ; i++) {
      NSString *utf16str = [stringFromBuffer (bytes + i, 22, VXUTF16LEStringEncoding) lowercaseString];
      NSString *utf8str  = [stringFromBuffer (bytes + i, 11, NSISOLatin1StringEncoding) lowercaseString];

      if (isprint (bytes[i]) && ([utf16str hasPrefix: @"vxsync"] || [utf8str hasPrefix: @"vxsync"])) {
	fprintf (stderr, "Found test contact at index: %d\n", entryIndex);
	pretty_print_block (bytes, ret);
	found = YES;
      }
    }

    memset (bytes, 0, 1024);
    bytes[0] = 0xf1;
    bytes[1] = 0x01;
  
    (void) [[phone efs] send_recv_message: bytes sendLength: 4 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];
  }
}

@synthesize phone, buffer;

@end

int main (void) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSSet *devices;

  [vxSyncLogger setDefaultLogger: [vxSyncLogger loggerWithLevel: 0 logFd: -1 progName: @"LGPBTestDump"]];

  devices = [IOUSBPhone scanDevices];

  for (id device in devices) {
    NSArray *locationComponents = [device componentsSeparatedByString: @"::"];
    vxPhone *phone = [vxPhone phoneWithLocation: device];

    fprintf (stderr, "Checking device @ %s: %p\n", [[device description] UTF8String], phone);
    fprintf (stderr, "device info = %s\n", [[[[phone efs] phoneInfo] description] UTF8String]);

    LGPBTestDump *dumped = [LGPBTestDump newWithPhone: phone];
  }

  [vxSyncLogger setDefaultLogger: nil];

  [releasePool release];

  return 0;
}
