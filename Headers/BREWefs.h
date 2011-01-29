/* (-*- objc -*-)
 * vxSync: BREWefs.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.3
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(BREWEFS_H)
#define BREWEFS_H

#include "VXSync.h"

#include "IOUSBPhone.h"
#include "IOBluetoothPhone.h"

extern struct _devices supported_models[];

#define BREW_MAX_OPEN 30

@interface BREWefs : NSObject <EFS> {
  BOOL requiresReboot;
@private
  NSString *meid, *identifier, *mtn, *carrier, *model, *version;
  NSDictionary *bluetooth;

  int brewVersion, extra;
  NSMutableData *_sendBuffer, *_recvBuffer;
  
  id <PhoneDevice> device;
	
  struct brew_file_des {
    unsigned int brew_fd;
    size_t file_offset;
    size_t file_size;
    int is_open;
    int is_dir;
    int flags;
  } filedes[BREW_MAX_OPEN];
}

@property(readwrite) BOOL requiresReboot;
@property(retain) id <PhoneDevice> device;

@property (retain) NSString *meid;
@property (retain) NSString *identifier;
@property (retain) NSString *mtn;
@property (retain) NSString *carrier;
@property (retain) NSString *model;
@property (retain) NSString *version;
@property (retain) NSDictionary *bluetooth;

@property(retain) NSMutableData *_sendBuffer;
@property(retain) NSMutableData *_recvBuffer;
@property int brewVersion;

+ (id) efsWithDevice: (id <PhoneDevice>) d;
+ (NSString *) identifierForDevice: (id <PhoneDevice>) deviceIn;

- (int) send_recv_message: (unsigned char *) sbuffer sendLength: (size_t) sbuffer_len sendBufferSize: (size_t) sbuffer_size
                   recvTo: (unsigned char *) rbuffer recvLength: (size_t) rbuffer_len;

- (id) initWithDevice: (id <PhoneDevice>) d;
- (void) doneWithDevice;

- (void) dealloc;

- (NSDictionary *) phoneInfo;

- (int) reboot;
- (NSData *) get_file_data_from: (NSString *) filename errorOut: (NSString **) error;

/* file methods */
- (int) stat:(NSString *)filename to:(struct stat *)sb;
- (int) open:(NSString *)filename withFlags:(int)oflag, ...;
- (int) close:(int)fd;
- (ssize_t) read: (int) fd to: (unsigned char *) buf count: (size_t) len;
- (ssize_t) write: (int) fd from: (unsigned char *) buf count: (size_t) len;
- (off_t) lseek: (int) fd toOffset: (off_t) offset whence: (int) whence;

/* directory methods */
- (int) mkdir: (NSString *) filename withMode: (mode_t) mode;
- (DIR *)opendir: (NSString *) filename;
- (int) closedir: (DIR *) dirp;
- (struct dirent *) readdir: (DIR *) dirp;
- (long) telldir:(DIR *)dirp;

- (int) unlink: (NSString *) path;

- (int) chmod: (NSString *) path withMode: (mode_t) mode;

@end

#endif
