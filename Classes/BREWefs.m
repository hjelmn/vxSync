/* (-*- objc -*-)
 * vxSync: BREWefs.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.8.2 - Jan 8, 2011
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "BREWefs.h"

#define LOCKED2(s, r, ret)			\
  do {						\
    *(ret) = !(s) ? (r) : -1;			\
    if (*(ret)) {				\
      if (errno == EACCES) {			\
	[self enter_DM];			\
	*(ret) = !(s) ? (r) : -1;		\
      }						\
    }						\
  } while (0)

enum brew_commands {
  BREW_OPEN        = 0x02,
  BREW_CLOSE       = 0x03,
  BREW_READ        = 0x04,
  BREW_WRITE       = 0x05,
  BREW_UNLINK_FILE = 0x08,
  BREW_MKDIR       = 0x09,
  BREW_UNLINK_DIR  = 0x0a,
  BREW_OPENDIR     = 0x0b,
  BREW_READDIR     = 0x0c,
  BREW_CLOSEDIR    = 0x0d,
  BREW_STAT        = 0x0f,
  BREW_CHMOD       = 0x12
};

#define UNLOCK_MAGIC (unsigned char)0x5c
#define BREW2_MAGIC (unsigned short)0x134b
#define BREW1_MAGIC  (unsigned char)0x59
#define BREW_READ_SIZE 0x2000
#define BREW_WRITE_SIZE 0x1A00
#if !defined(PATH_MAX)
#define PATH_MAX 255
#endif

@interface BREWefs (hidden)
- (int) recv_response_to:(u_int16_t)brew_command, ...;
- (int) send_command:(u_int16_t)brew_command, ...;
- (int) send_message: (u_int8_t *) buffer withLength: (size_t) len bufferSize: (size_t) bufferLen;
- (int) recv_message:(unsigned char *)buffer withLength:(size_t)len;
- (u_int32_t) get_challenge_response:(u_int32_t)challenge;
- (int) send_recv_message: (unsigned char *) sbuffer sendLength: (size_t) sbuffer_len sendBufferSize: (size_t) sbuffer_size
                   recvTo: (unsigned char *) rbuffer recvLength: (size_t) rbuffer_len;
- (int) enter_DM;
- (int) getavailablefd;

- (void) readName;
- (void) readModel;
- (void) initUniqueID;
- (void) readCarrier;
- (void) readMEIDSWVersionMTN;
@end

@implementation BREWefs

#pragma mark allocation/initialization
+ (id) efsWithDevice: (id <PhoneDevice>) d {
  return [[[BREWefs alloc] initWithDevice: d] autorelease];
}

- (id) initWithDevice: (id <PhoneDevice>) d {
  self = [super init];
  if (!self || !d)
    return nil;
  
  @try {
    vxSync_log3(VXSYNC_LOG_INFO, @"initializing with device = %p\n", d);
    
    [self set_sendBuffer: [NSMutableData dataWithLength: 10000]];
    [self set_recvBuffer: [NSMutableData dataWithLength: 10000]];          
    [self setDevice: d];
    [self setBrewVersion: 2];
    
    memset (filedes, 0, sizeof (struct brew_file_des) * BREW_MAX_OPEN);
    
    int ret = [self.device open];
    if (ret < 0)
      [NSException raise: @"unable to open device" format: @"device returned error code = %d", ret];
    
    [self initUniqueID];
    [self readModel];
    [self readName];
    [self readCarrier];
    [self readMEIDSWVersionMTN];
    [self setRequiresReboot: NO];
  } @catch (id exception) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"failed to initialize from device. Reason: %s\n", NS2CH(exception));
    
    [self doneWithDevice];
    return nil;
  }
  
  vxSync_log3(VXSYNC_LOG_INFO, @"BREW protocol initialized with device: %s of type %s\n", NS2CH([self valueForKey: @"identifier"]), NS2CH([device class]));
  
  return self;
}

- (void) readMEIDSWVersionMTN {
  u_int8_t *buffer = [_recvBuffer mutableBytes];
  int ret;

  memset(buffer, 0, 4);
  buffer[0] = 0xf1;
  buffer[1] = 0x0a;
  
  ret = [self send_recv_message: buffer sendLength: 4 sendBufferSize: [_recvBuffer length] recvTo: buffer recvLength: [_recvBuffer length]];
  if (ret < 0)
    [NSException raise: @"Could not read phone data" format: @"%s", strerror (errno)];

  [self setVersion: @"Unknown"];
  [self setMeid: @"Unknown"];
  [self setMtn: @"Unknown"];
  
  if (strlen((char *)buffer + 173))
    [self setVersion: [NSString stringWithUTF8String: (char *)buffer + 173]];

  if (strlen ((char *)buffer + 529))
    [self setMeid: [NSString stringWithUTF8String: (char *)buffer + 529]];

  if (strlen ((char *)buffer + 10))
    [self setMtn: formattedNumber((char *)buffer + 10)];

  vxSync_log3(VXSYNC_LOG_INFO, @"%s", NS2CH(([self dictionaryWithValuesForKeys: [NSArray arrayWithObjects: @"version", @"meid", @"mtn", nil]])));
}

- (void) readName {
  u_int8_t *buffer = [_recvBuffer mutableBytes];
  NSString *error, *btName = nil, *btAddress = nil;
  NSData *fileData;
  int ret;

  /* get phone bluetooth identifier (as name) */
  fileData =  [self get_file_data_from: @"bluetooth/btMyDev" errorOut: &error];
  if (fileData) {
    unsigned char *dataBytes = (unsigned char *) [fileData bytes];

    vxSync_log3_data(VXSYNC_LOG_DATA, fileData, @"btMyDev data\n");

    /* XXX -- this may not be the same on all supported phones (it isn't :-/) */
    btName = [NSString stringWithUTF8String: (char *)dataBytes + ((dataBytes[6] != 0) ? 6 : 12)];
  } else {
    fileData = [self get_file_data_from: @"BT Params" errorOut: &error];
    
    if (fileData)
      btName = [NSString stringWithUTF8String: (char *)[fileData bytes] + 1];
  }

  /* read bluetooth MAC */
  memset (buffer, 0, 136);
  buffer[0] = 0x26;
  buffer[1] = 0xbf;
  buffer[2] = 0x01;

  ret = [self send_recv_message: buffer sendLength: 133 sendBufferSize: [_recvBuffer length] recvTo: buffer recvLength: [_recvBuffer length]];
  if (ret < 0)
    [NSException raise: @"Could not read phone data" format: @"%s", strerror (errno)];

  btAddress = [NSString stringWithFormat: @"%02x-%02x-%02x-%02x-%02x-%02x", buffer[8], buffer[7], buffer[6], buffer[5], buffer[4], buffer[3]];

  [self setBluetooth: [NSMutableDictionary dictionary]];

  [self setValue: btName ? btName : @"Unknown" forKeyPath: @"bluetooth.name"];
  if (btAddress)
    [self setValue: btAddress forKeyPath: @"bluetooth.address"];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"phone bluetooth name: %s\n", NS2CH([self valueForKeyPath: @"bluetooth.name"]));
  vxSync_log3(VXSYNC_LOG_INFO, @"phone bluetooth address: %s\n", NS2CH([self valueForKeyPath: @"bluetooth.address"]));
}

- (void) readModel {
  NSData *fileData;
  NSString *error = nil;

  fileData = [self get_file_data_from: @"brew/version.txt" errorOut: &error];
  if (fileData) {
    NSString *textData = [[[NSString alloc] initWithData: fileData encoding: NSUTF8StringEncoding] autorelease];
    NSArray *fields = [textData componentsSeparatedByString: @","];
    
    /* the first field is the model. we don't care about the other fields atm */
    vxSync_log3(VXSYNC_LOG_DATA, @"contents of brew/version.txt: %s\n", NS2CH(textData));
    if ([fields count] && ([[fields objectAtIndex: 0] hasPrefix: @"VX"] || [[fields objectAtIndex: 0] hasPrefix: @"CX"] ||
                           [[fields objectAtIndex: 0] hasPrefix: @"AX"] || [[fields objectAtIndex: 0] hasPrefix: @"VN"]))
      [self setModel: [fields objectAtIndex: 0]];
    else
      [NSException raise: @"error parsing read brew/version.txt" format: @"file data = %@", fileData];
  } else
    [NSException raise: @"error reading read brew/version.txt" format: @"%@", error];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"phone model number: %s\n", NS2CH(model));
}

+ (NSString *) identifierForDevice: (id <PhoneDevice>) deviceIn {
  BREWefs *_efs = [[[BREWefs alloc] init] autorelease];
  int ret;

  [_efs set_recvBuffer: [NSMutableData dataWithLength: 10000]];          
  [_efs setDevice: deviceIn];
  ret = [deviceIn open];
  if (ret < 0) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open device\n");
    return nil;
  }
  [_efs initUniqueID];
  [_efs doneWithDevice];

  return [[[_efs identifier] copy] autorelease];
}

- (void) initUniqueID {
  u_int8_t *buffer = [_recvBuffer mutableBytes];
  int ret;

  /* send brew command 0x01 (get ESN) */
  buffer[0] = 0x01;
  ret = [self send_recv_message: buffer sendLength: 1 sendBufferSize: 20 recvTo: buffer recvLength: [_recvBuffer length]];
  if (ret < 0)
    [NSException raise: @"Could not read ESN" format: @"%s", strerror (errno)];

  [self setIdentifier: [NSString stringWithFormat: @"%08x", crc32(buffer + 1, 4)]];

  vxSync_log3(VXSYNC_LOG_INFO, @"phone unique ID: %s\n", NS2CH([self valueForKey: @"identifier"]));
}

- (void) readCarrier {
  u_int8_t *buffer = [_recvBuffer mutableBytes];
  int ret;
  
  memset (buffer, 0, 4);
  /* send brew command 0x01 (get ESN) */
  buffer[0] = 0xf1;
  buffer[1] = 0x01;
  ret = [self send_recv_message: buffer sendLength: 4 sendBufferSize: 20 recvTo: buffer recvLength: [_recvBuffer length]];
  if (ret < 0)
    [NSException raise: @"Could not read carrier name" format: @"%s", strerror (errno)];

  if (strlen ((char *)(buffer + 0x26)))
    [self setCarrier: [NSString stringWithUTF8String: (char *)(buffer + 0x26)]];
  else
    [self setCarrier: @"Not Available"];

  vxSync_log3(VXSYNC_LOG_INFO, @"phone carrier: %s\n", NS2CH([self valueForKey: @"carrier"]));
}

- (NSDictionary *) phoneInfo {
  return [self dictionaryWithValuesForKeys: [NSArray arrayWithObjects: @"model", @"mtn", @"version", @"identifier", @"bluetooth", @"carrier", @"meid", nil]];
}

#pragma mark deallocation
- (void) doneWithDevice {
  vxSync_log3(VXSYNC_LOG_INFO, @"closing and releasing device\n");
  [device close];
  [self setDevice: nil];
}

- (void) dealloc {
  vxSync_log3(VXSYNC_LOG_INFO, @"dealloc called for BREWefs object %p\n", self);

  [self doneWithDevice];

  [self setVersion: nil];
  [self setMtn: nil];
  [self setMeid: nil];
  [self setIdentifier: nil];
  [self setBluetooth: nil];
  [self setCarrier: nil];
  [self setModel: nil];

  [self set_recvBuffer: nil];
  [self set_sendBuffer: nil];

  [super dealloc];
}

#pragma mark properties synthesized

@synthesize requiresReboot, brewVersion;

/* these need to be released in dealloc using setName: nil */
@synthesize device, _sendBuffer, _recvBuffer;
@synthesize version, mtn, meid, identifier, bluetooth, carrier, model;

- (int) reboot {
  if (self.requiresReboot) {
    unsigned char buffer[9] = {0x29, 0x01, 0x00,};
    vxSync_log3(VXSYNC_LOG_INFO, @"rebooting phone...\n");

    [self send_recv_message: buffer sendLength: 3 sendBufferSize: 9 recvTo: buffer recvLength: 9];
    buffer[1] = 0x02;
    return [self send_recv_message: buffer sendLength: 3 sendBufferSize: 9 recvTo: buffer recvLength: 9];
  }

  return 0;
}

- (int) write_file_data: (NSData *) data to: (NSString *) filename {
  int fd, ret;
  
  fd = [self open: filename withFlags: O_WRONLY | O_TRUNC | O_CREAT];
  if (fd < 0)
    return -1;
  
  ret = [self write: fd from: (unsigned char *) [data bytes] count: [data length]];
  [self close: fd];
  
  return ret;
}

- (NSData *) get_file_data_from: (NSString *) filename errorOut: (NSString **) error {
  unsigned char *buffer;
  int fd, ret;
  struct stat statinfo;
  
  assert (nil != filename);
  
  ret = [self stat: filename to:&statinfo];
  if (ret < 0) {
    if (error)
      *error = [NSString stringWithFormat: @"%s: could not stat %@. Reason: %s", __func__, filename, strerror (errno)];
    return nil;
  }
  if (0 == statinfo.st_size) {
    /* empty file */
    if (error) *error = nil;
    return nil;
  }
  
  vxSync_log3(VXSYNC_LOG_INFO, @"allocating %i bytes for file data\n", (int)statinfo.st_size);
  
  buffer = calloc (statinfo.st_size, 1);
  if (!buffer) {
    if (error)
      *error = [NSString stringWithFormat: @"%s: could not allocate memory for data buffer. Reason: %s", __func__, strerror (errno)];
    return nil;
  }
  
  fd = [self open: filename withFlags: O_RDONLY];
  if (fd < 0) {
    if (error)
      *error = [NSString stringWithFormat: @"%s: could open file %@ for reading. Reason: %s", __func__, filename, strerror (errno)];
    return nil;
  }
  
  ret = [self read: fd to: (unsigned char *) buffer count: (size_t) statinfo.st_size];
  [self close: fd];
  if (ret < statinfo.st_size) {
    if (ret == -1) {
      if (error)
	*error = [NSString stringWithFormat: @"%s: could not read from file %@. Reason: %s", __func__, filename, strerror (errno)];

      return nil;
    }
    /* short read */
  }

  vxSync_log3(VXSYNC_LOG_INFO, @"read %d bytes from file\n", ret);
  
  return [NSData dataWithBytes: buffer length: ret];
}

- (ssize_t) read: (int) fd to: (unsigned char *) buffer count: (size_t) len {
  u_int32_t rsize;
  int bytes_read, ret, file_left;
  
  if (buffer == NULL) {
    errno = EFAULT;

    return -1;
  }

  /* the last check verifies that the file is open for reading */
  if ((unsigned int)fd >= BREW_MAX_OPEN || filedes[fd].is_open == 0 || filedes[fd].is_dir != 0 || (filedes[fd].flags & (O_CREAT | O_WRONLY)) == (O_CREAT | O_WRONLY)) {
    errno = EBADF;

    return -1;
  }
  
  for (bytes_read = 0 ; bytes_read < len ; ) {
    file_left = filedes[fd].file_size - filedes[fd].file_offset;
    rsize = ((len - bytes_read) > BREW_READ_SIZE) ? BREW_READ_SIZE : len - bytes_read;
    if (rsize > file_left)
      rsize = file_left;
    
    if (rsize) {
      LOCKED2(([self send_command: BREW_READ, filedes[fd].brew_fd, rsize, filedes[fd].file_offset]),
              ([self recv_response_to: BREW_READ, NULL, NULL, &rsize, buffer + bytes_read]), &ret);
      if (ret < 0)
        return -1;
    }
    
    bytes_read += rsize;
    
    /* set the new offset */
    filedes[fd].file_offset = filedes[fd].file_offset + rsize;
    
    if (rsize == 0)
      break;
  }
  
  return bytes_read;
}

- (ssize_t) write: (int) fd from: (unsigned char *) buffer count: (size_t) len {
  int bytes_written, ret, wsize;

  if (buffer == NULL) {
    errno = EFAULT;

    return -1;
  }

  if (fd < 0 || fd >= BREW_MAX_OPEN || filedes[fd].is_open == 0 || filedes[fd].is_dir != 0) {
    errno = EBADF;

    return -1;
  }

  bytes_written = 0;

  while (bytes_written < len) {
    wsize = ((len - bytes_written) > BREW_WRITE_SIZE) ? BREW_WRITE_SIZE : len - bytes_written;
    
    LOCKED2(([self send_command: BREW_WRITE, filedes[fd].brew_fd, filedes[fd].file_offset, wsize, buffer + bytes_written]),
	    ([self recv_response_to: BREW_WRITE, NULL, NULL, &wsize]), &ret);
    if (ret < 0)
      return -1;
    
    if (wsize == 0)
      break;
    
    bytes_written += wsize;
    
    /* update the file size */
    if (!(filedes[fd].flags & O_APPEND)) {
      /* set the new offset if not in append mode */
      filedes[fd].file_offset = filedes[fd].file_offset + wsize;
      
      /* update the file size */
      if (filedes[fd].file_offset > filedes[fd].file_size)
        filedes[fd].file_size = filedes[fd].file_offset;
    } else
      filedes[fd].file_size += wsize;
  }
  
  return bytes_written;
}

- (int) open: (NSString *) filename withFlags: (int) flags, ... {
/*  va_list ap;
  off_t mode; */
  int fd, ret;
  u_int32_t brew_flags1, brew_flags2;
  struct stat statinfo;
  
  ret = [self stat: filename to: &statinfo];
  if (!ret && ((flags & (O_CREAT | O_EXCL)) == (O_CREAT | O_EXCL))) {
    errno = EEXIST;
    return -1;
  } else if (ret < 0 && !(flags & O_CREAT))
    return -1;
  
  /*
  if (flags & O_CREAT) {
    va_start (ap, flags);
    mode = va_arg (ap, int);
  }
   */
  
  fd = [self getavailablefd];
  if (fd < 0)
    return fd;
  
  brew_flags1    = 0x000;

  if (flags & O_WRONLY)
    brew_flags1 |= 0x001;
  if (flags & O_RDWR)
    brew_flags1 |= 0x002;
  if (flags & O_TRUNC)
    brew_flags1 |= 0x200;
  if (flags & O_APPEND)
    brew_flags1 |= 0x400;
  
  brew_flags1 |= (flags & O_CREAT) ? 0x40 : 0;
  brew_flags2 = (flags & O_CREAT) ? 1 : 0;

  LOCKED2 (([self send_command: BREW_OPEN, brew_flags1, brew_flags2, [filename UTF8String]]),
	   ([self recv_response_to: BREW_OPEN, &filedes[fd].brew_fd]), &ret);
  if (ret < 0) {
    filedes[fd].is_open = 0;
    return -1;
  }
  
  filedes[fd].is_open = 1;
  if (!(flags & O_CREAT)) {
    filedes[fd].file_offset = 0;
    filedes[fd].file_size   = (flags & O_TRUNC) ? 0 : (int)statinfo.st_size;
  } else {
    filedes[fd].file_offset = 0;
    filedes[fd].file_size   = 0;
  }
  
  filedes[fd].flags = flags;
  
  return fd;
}

- (int) close: (int)fd {
  int ret;

  if (fd <  0 || fd >= BREW_MAX_OPEN || filedes[fd].is_open == 0 || filedes[fd].is_dir != 0) {
    errno = EBADF;
    
    return -1;
  }
  
  ret = [self send_command: BREW_CLOSE, filedes[fd].brew_fd];
  ret = ret ? ret : [self recv_response_to: BREW_CLOSE];
  
  filedes[fd].is_open = 0;
  return ret;
}

- (int) stat: (NSString *) filename to: (struct stat *) sb {
  int ret;
  u_int32_t mode, size, unk1, atime, mtime, ctime;
  
  assert(filename != NULL);
  
  if ([filename length] > PATH_MAX) {
    errno = ENAMETOOLONG;
    
    return -1;
  }

  LOCKED2 (([self send_command: BREW_STAT, [filename UTF8String]]), ([self recv_response_to: BREW_STAT, &mode, &size, &unk1, &atime, &mtime, &ctime]), &ret);
  if (ret < 0)
    return -1;
  
  if (sb != NULL) {
    memset (sb, 0, sizeof (struct stat));
    
    /* these should probably be root/wheel if the file is protected */
    sb->st_uid   = getuid ();
    sb->st_gid   = getgid ();
    
    sb->st_size  = (off_t)size;
    
    /* these probably need to be converted to GMT */
    sb->st_atime = atime;
    sb->st_mtime = mtime;
    sb->st_ctime = ctime;
    
    /* set file mode and nlinks */
    /* the phone returns a UNIX file mode */
    sb->st_mode = mode;
    sb->st_nlink = (S_ISDIR(mode)) ? size : 1;    
  }

  return 0;
}

/* this version of lseek is NOT compatible with the POSIX call in that we can only
 seek to the end of the file (not past it) */
- (off_t) lseek: (int) fd toOffset: (off_t) offset whence: (int) whence {
  if (fd < 0 || fd >= BREW_MAX_OPEN || filedes[fd].is_open == 0 || filedes[fd].is_dir != 0) {
    errno = EBADF;
    
    return -1;
  }
  
  switch (whence) {
    case SEEK_SET:
      filedes[fd].file_offset = 0;
    case SEEK_CUR:
      filedes[fd].file_offset += offset;
      break;
    case SEEK_END:
      filedes[fd].file_offset = filedes[fd].file_size + offset;
      break;
    default:
      errno = EINVAL;
      
      return -1;
  }
  
  /* range check on the offset */
  if (filedes[fd].file_offset > filedes[fd].file_size)
    filedes[fd].file_offset = filedes[fd].file_size;
  else if (filedes[fd].file_offset < 0)
    filedes[fd].file_offset = 0;

  return (off_t)filedes[fd].file_offset;
}

- (int) mkdir: (NSString *) filename withMode: (mode_t) mode {
  struct stat statinfo;
  int ret;

  if ([filename length] > PATH_MAX) {
    errno = ENAMETOOLONG;

    return -1;
  }
  
  ret = [self stat: [filename stringByDeletingLastPathComponent] to: &statinfo];
  if (ret < 0)
  /* errno should already have been set by brew_stat */
    return ret;

  if (!S_ISDIR(statinfo.st_mode)) {
    errno = ENOTDIR;

    return -1;
  }

  /* ok to try to make the directory */
  ret = [self send_command: BREW_MKDIR, mode & 0x1ff, [filename UTF8String]];
  ret = ret ? ret : [self recv_response_to: BREW_MKDIR];

  return ret;
}

- (int) unlink: (NSString *) path {
  int ret;
  
  LOCKED2 (([self send_command: BREW_UNLINK_FILE, [path UTF8String]]), ([self recv_response_to: BREW_UNLINK_FILE]), &ret);
  
  return ret;
}

- (int) chmod: (NSString *) path withMode: (mode_t) mode {
  int ret;

  LOCKED2 (([self send_command: BREW_CHMOD, mode, [path UTF8String]]), ([self recv_response_to: BREW_CHMOD]), &ret);

  return ret;
}

- (DIR *) opendir: (NSString *) filename {
  int ret, fd;
  
  struct stat statinfo;
  DIR *dh;
  
  if ([filename length] > PATH_MAX) {
    errno = ENAMETOOLONG;
    
    return NULL;
  }
  
  ret = [self stat: filename to: &statinfo];
  if (ret < 0)
  /* errno should already have been set by brew_stat */
    return NULL;
  
  if (!S_ISDIR(statinfo.st_mode)) {
    errno = ENOTDIR;
    
    return NULL;
  }
  
  /* allocate a file descriptor */
  fd = [self getavailablefd];
  if (fd < 0)
    return NULL;
  
  filedes[fd].is_dir = 1;
  filedes[fd].file_size = statinfo.st_size - 2;
  
  /* tell the phone to open the directory */
  ret = [self send_command: BREW_OPENDIR, [filename UTF8String]];
  ret = ret ? ret : [self recv_response_to: BREW_OPENDIR, &filedes[fd].brew_fd];
  if (ret < 0) {
    filedes[fd].is_open = 0;

    return NULL;
  }
  
  /* success. build directory structure */
  dh = calloc (1, sizeof (DIR));
  dh->__dd_buf = calloc (1, sizeof (struct dirent));

  dirfd(dh) = fd;
  filedes[fd].file_offset = 1;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"opened dir %s with fd: %i and pos: %u\n", [filename UTF8String], fd, (unsigned int)filedes[fd].file_offset);
  
  return dh;
}

- (int) closedir: (DIR *) dirp {
  int fd, ret;
  
  if (!dirp || (fd = dirfd(dirp) < 0)) {
    errno = EBADF;
    return -1;
  }
  
  ret = [self send_command: 0x000d, filedes[fd].brew_fd];
  ret = ret ? ret : [self recv_response_to: 0x000d];
  
  filedes[fd].is_open = 0;

  free (dirp->__dd_buf);
  free (dirp);
  
  return ret;
}

- (struct dirent *) readdir: (DIR *) dirp {
  int fd, ret;
  u_int32_t ch_fd, index, flag, mode, size, date;
  struct dirent *dir_entry;
  
  if (!dirp || ((fd = dirfd (dirp)) < 0)) {
    errno = EBADF;
    return NULL;
  }

  if (filedes[fd].file_offset <= 0 || filedes[fd].file_offset > filedes[fd].file_size) {
    errno = ENOENT;
    return NULL;
  }

  dir_entry = (struct dirent *) dirp->__dd_buf;
  memset (dir_entry, 0, sizeof (struct dirent));
  
  ret = [self send_command: BREW_READDIR, (unsigned int)filedes[fd].brew_fd, (unsigned int)filedes[fd].file_offset];
  ret = ret ? ret : [self recv_response_to: BREW_READDIR, &ch_fd, &index, &flag, &mode, &size, &date, dir_entry->d_name, (u_int32_t)255];
  if (ret < 0 || strlen (dir_entry->d_name) == 0)
    return NULL;

  dir_entry->d_type   = (flag & 0x1) ? DT_DIR : DT_REG;
  dir_entry->d_namlen = strlen (dir_entry->d_name);
  dir_entry->d_reclen = sizeof (struct dirent) - sizeof (dir_entry->d_name) + dir_entry->d_namlen + 1;

  filedes[fd].file_offset ++;

  return dir_entry;
}

- (long) telldir: (DIR *) dirp {
  int fd;
  
  if (!dirp || (fd = dirfd (dirp) < 0)) {
    errno = EBADF;
    return -1;
  }
  
  return filedes[fd].file_offset;
}

- (int) seekdir: (DIR *) dirp to: (long)loc {
  int fd;
  
  if (!dirp || (fd = dirfd (dirp) < 0)) {
    errno = EBADF;
    return -1;
  }
  
  /* XXX - need to check loc and see whether or not it is valid */
  
  filedes[fd].file_offset = (off_t)loc;
  
  return 0;
}

- (int) getavailablefd {
  int i;
  
  for (i = 0 ; i < BREW_MAX_OPEN ; i++)
    if (filedes[i].is_open == 0) {
      memset (&filedes[i], 0, sizeof (struct brew_file_des));
      filedes[i].is_open = 1;

      return i;
    }
  
  errno = EMFILE;
  return -1;
}
/* end internal helper functions */

- (int) recv_response_to: (u_int16_t)brew_command, ... {
  va_list ap;
  u_int8_t *buffer, *ptr;
  u_int16_t error16;
  u_int32_t error32 = 0;
  int ret;
  
  ptr = buffer = [_recvBuffer mutableBytes];

  ret = [self recv_message: buffer withLength: [_recvBuffer length]];
  if (ret < 0)
    return ret;
  
  va_start (ap, brew_command);
  
  /* unpack standard header */
  unpackValue(&ptr, NULL, 2);
  unpackValue(&ptr, &error16, 2);

  /* alternate way access denied can be returned */
  if (error16 == 0x1c || buffer[0] == 0x13 || buffer[0] == 0x14) {
    errno = EACCES;
    
    return -1;
  } else if (error16 != brew_command) {
    errno = EPERM;
    
    return -1;
  }

  switch (brew_command) {
    case BREW_OPEN:
    case BREW_OPENDIR:
      /* open dir/file response */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* file descriptor */
      unpackValue (&ptr, &error32, 4);                 /* error code */
      
      break;
    case BREW_CLOSE:
    case BREW_CLOSEDIR:
    case BREW_UNLINK_FILE:
    case BREW_UNLINK_DIR:
    case BREW_CHMOD:
      /* close/unlink file/dir, chmod response */
      unpackValue (&ptr, &error32, 4);                 /* error code */

      break;
    case BREW_READ: {
      /* read response */
      u_int32_t *bytes_read;
      
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* file descriptor */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* position */
      bytes_read = va_arg (ap, u_int32_t *);
      unpackValue (&ptr, bytes_read, 4);               /* bytes read */
      unpackValue (&ptr, &error32, 4);                 /* error code */

      if (*bytes_read != 0xffff && !error32)
        unpackString(&ptr, va_arg (ap, char *), *bytes_read); /* data */
      
      break;
    }
    case BREW_WRITE:
      /* write response */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* file descriptor */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* position */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* bytes_written */
      unpackValue (&ptr, &error32, 4);                 /* error code */

      break;
    case BREW_READDIR: {
      char *filename;
      size_t namelen;

      /* readdir response */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* file descriptor */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* index */
      unpackValue (&ptr, NULL, 4);                     /* nothing */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* dir flag */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* file mode */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* file size */
      unpackValue (&ptr, NULL, 4);                     /* nothing */
      unpackValue (&ptr, NULL, 4);                     /* nothing */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* date */
      
      filename = va_arg (ap, char *);
      namelen  = va_arg (ap, u_int32_t);
      strncpy (filename, (char *)ptr, namelen);
      
      break;
    } case BREW_STAT:

      /* stat response */
      unpackValue (&ptr, &error32, 4);                 /* error code */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* unknown */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* link count/size */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* link count?? */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* atime */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* mtime */
      unpackValue (&ptr, va_arg (ap, u_int32_t *), 4); /* ctime */
      
      break;
    default:
      /* unknown or unpack complete */
      break;
  }
  
  va_end (ap);
  
  if (error32) {
    errno = error32;
    return -1;
  }

  return 0;
}

-(int)send_command: (u_int16_t) brew_command, ... {
  va_list ap;
  u_int8_t *optr, *ptr;
  char *tmp;
  int ret;

  if (self.brewVersion == 1) {
    errno = ENODEV;

    return -1; /* not supported */
  }

  optr = ptr = [_sendBuffer mutableBytes];

  va_start (ap, brew_command);
  
  /* pack message header */
  if (self.brewVersion >= 2) {
    packValue (&ptr, BREW2_MAGIC, 2);
    packValue (&ptr, brew_command, 2);                  /* message type */
  } else {
    packValue (&ptr, BREW1_MAGIC, 1);
    packValue (&ptr, (unsigned char)brew_command, 1);
  }
  
  /* pack message data */
  switch (brew_command) {
    case BREW_OPEN:
      /* open file */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* brew_flags1 */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* brew_flags2 */
      packString (&ptr, va_arg (ap, char *), -1);       /* filename */
      
      break;
    case BREW_CLOSE:
    case BREW_CLOSEDIR:
      /* close file/dir */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* brew file/dir descriptor */
      
      break;
    case BREW_READ:
      /* read */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* brew file descriptor */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* from position */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* size */
      
      break;
    case BREW_UNLINK_FILE:
      /* rm/rmdir/opendir/stat */
      tmp = va_arg (ap, char *);
      packString (&ptr, tmp, -1); /* filename */
      packValue (&ptr, 1, 1);
      
      break;
    case BREW_UNLINK_DIR:
    case BREW_OPENDIR:
    case BREW_STAT:
      /* rm/rmdir/opendir/stat */
      tmp = va_arg (ap, char *);
      packString (&ptr, tmp, -1); /* filename */
      
      break;
    case BREW_MKDIR:
    case BREW_CHMOD:
      /* mkdir */
      packValue (&ptr, va_arg (ap, unsigned int), 2); /* mode (usually 0777) */
      packString (&ptr, va_arg (ap, char *), -1);      /* filename */
      
      break;
    case BREW_READDIR:
      /* readdir */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* brew dir descriptor */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* index */
      
      break;
    case BREW_WRITE: {
      u_int32_t size;
      /* write */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* brew file descriptor */
      packValue (&ptr, va_arg (ap, unsigned int), 4); /* from position */
      size = va_arg (ap, unsigned int);

      if ((ptr - optr) + size > [_sendBuffer length]) {
        errno = ENOBUFS;

        return -1;
      }

      memmove (ptr, va_arg (ap, char *), size);
      ptr += size;

      break;
    }
    default:
      vxSync_log3(VXSYNC_LOG_ERROR, @"unknown/unsupported message type 0x%04x\n", brew_command);
      
      va_end (ap);
      
      return -1;
  }
  
  va_end (ap);
  
  ret = [self send_message: optr withLength: (int)(ptr - optr) bufferSize: 8192];
  return (ret < 0) ? ret : 0;
}

- (int) send_message:(u_int8_t *)buffer withLength:(size_t)len bufferSize: (size_t) bufferLen {
  return [[self device] write_message: buffer withLength: len bufferSize: bufferLen];
}

- (int) recv_message: (unsigned char *) buffer withLength: (size_t) len {
  int ret = [[self device] read_message: buffer length: len];
  if (ret == -1)
    return ret;
  
  if (buffer[0] == 0x13) {
    errno = EACCES;
    
    return -1;
  } else if (buffer[0] == 0x14) {
    errno = ENODEV;
    
    return -1;
  }
  
  return ret;
}

#define ROTATEL(x,i) ((x << i) | (x >> (32-i)))

- (u_int32_t) get_challenge_response: (u_int32_t)challenge {
  u_int32_t sha_buffer[16];
  u_int32_t hash_result[5] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0};
  u_int32_t hash_iv[5] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0};
  u_int32_t f, k, newA;
  int i, j, index1, index2, index3;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"finding response for challenge: %08x\n", challenge);
  
  sha_buffer[0] = challenge;
  memset (&sha_buffer[1], 0, 14 * sizeof (u_int32_t));
  sha_buffer[15] = 56;
  
  for (i = 0 ; i < 80 ; i++) {
    j = i & 0x0f;
    
    if (i > 15) {
      index1 = (i -  3) & 0x0f;
      index2 = (i -  8) & 0x0f;
      index3 = (i - 14) & 0x0f;
      
      sha_buffer[j] ^= sha_buffer[index1] ^ sha_buffer[index2] ^ sha_buffer[index3];
      sha_buffer[j] = ROTATEL(sha_buffer[j], 1);
    }
    
    if (i < 20) {
      f = (hash_result[1] & hash_result[2]) | ((~hash_result[1]) & hash_result[3]);
      k = 0x5a827999;
    } else if (i < 40) {
      f = hash_result[1] ^ hash_result[2] ^ hash_result[3];
      k = 0x6ed9eba1;
    } else if (i < 60) {
      f = (hash_result[1] & hash_result[2]) | (hash_result[1] & hash_result[3]) | (hash_result[2] & hash_result[3]);
      k = 0x8f1bbcdc;
    } else {
      f = hash_result[1] ^ hash_result[2] ^ hash_result[3];
      k = 0xca62c1d6;
    }
    
    newA = (hash_result[4] + ROTATEL(hash_result[0], 5) + sha_buffer[j] + f + k);
    
    for (j = 4 ; j > 0 ; j--)
      hash_result[j] = hash_result[j-1];
    
    hash_result[0] = newA;
    hash_result[2] = ROTATEL(hash_result[2], 30);
  }
  
  for (i = 0 ; i < 5 ; i++)
    hash_result[i] += hash_iv[i];
  
  return 0x80000000 | (hash_result[4] & 0x00ffffff);
}

- (int) send_recv_message: (unsigned char *) sbuffer sendLength: (size_t) sbuffer_len sendBufferSize: (size_t) sbuffer_size
                   recvTo: (unsigned char *) rbuffer recvLength: (size_t) rbuffer_len {
  int ret;
  
  ret = [self send_message: sbuffer withLength: sbuffer_len bufferSize: sbuffer_size];
  if (ret < 0)
    return ret;
  
  return [self recv_message: rbuffer withLength: rbuffer_len];
}

- (int) enter_DM {
  u_int8_t *buffer, *ptr;
  u_int32_t challenge, sha1;
  int i, ret, shift, count;
  char response_code;
  size_t buffer_length;

  buffer_length = [_sendBuffer length];
  buffer = [_sendBuffer mutableBytes];

  buffer[0] = 0xfe;
  memset (&buffer[1], 0, 6);
  
  ret = [self send_recv_message: buffer sendLength: 7 sendBufferSize: 50 recvTo: buffer recvLength: buffer_length];
  if (ret < 0 || buffer[0] != 0xfe) {
    unsigned char unlock_number[] = "\xa6Q3733929Q";

    /* old download mode */
    buffer[0] = 0x20;
    buffer[1] = 0x00;
    
    for (i = 0 ; i < strlen ((char *)unlock_number) ; i++) {
      buffer[2] = unlock_number[i];
      buffer[3] = (unlock_number[i] < 0x40) ? 0x10 : 0;
      
      ret = [self send_recv_message: buffer sendLength: 4 sendBufferSize: 50 recvTo: buffer recvLength: buffer_length];
      if (ret < 0)
        return -1;
    }
    
    return 0;
  }
  
  response_code = buffer[1];
  vxSync_log3(VXSYNC_LOG_INFO, @"challenge/response code: %02x\n", response_code);
  ptr = buffer + 2;
  unpackValue (&ptr, &challenge, 4);
  sha1 = [self get_challenge_response: challenge];
  
  if (0x02 == response_code) {
    /* 2008 download mode */
    vxSync_log3(VXSYNC_LOG_INFO, @"2008 DM: challenge/response code: %02x\n", response_code);
    
    shift = (extra >= 0) ? extra : 0;
    count = 0;
    
    /* shift will be calculated in the future */
    do {
      ptr = buffer;
      packValue (&ptr, 0xfe, 1);
      packValue (&ptr, 0x03, 1);
      packValue (&ptr, sha1, 4);
      packValue (&ptr, 0, 2);
      
      sha1 = ~sha1;
      for (i = 0 ; i < 4 ; i++)
        packValue (&ptr, 0x01010101 * ((sha1 >> (8 * ((i + shift) % 4))) & 0xff), 4);
      
      ret = [self send_recv_message: buffer sendLength: 24 sendBufferSize: 50 recvTo: buffer recvLength: 30];
      if (ret < 0)
        return -1;
      
      if (buffer[6] == 1)
        break;
      
      /* try another shift (up to 4 will be tried) */
      shift = (shift + 1) % 4;
      count ++;
      
      buffer[0] = 0xfe;
      memset (&buffer[1], 0, 6);
      
      ret = [self send_recv_message: buffer sendLength: 7 sendBufferSize: 50 recvTo: buffer recvLength: buffer_length];
      if (ret < 0)
        return -1;
      
      ptr = buffer + 2;
      unpackValue (&ptr, &challenge, 4);
      sha1 = [self get_challenge_response: challenge];
    } while (count < 4);
    
    if (buffer[6] != 1) {
      errno = EACCES;
      
      return -1;
    }
    
    extra = shift;
  } else {
    /* 2007 download mode */
    vxSync_log3(VXSYNC_LOG_INFO, @"2007 DM: challenge/response code: %02x\n", response_code);
    
    packValue (&ptr, 0x01, 1);
    packValue (&ptr, sha1, 4);
    packValue (&ptr, 0x00, 1);
    
    ret = [self send_recv_message: buffer sendLength: 7 sendBufferSize: 50 recvTo: buffer recvLength: buffer_length];
    if (ret < 0)
      return -1;
    
    if (buffer[6] != 1) {
      errno = EACCES;
      
      return -1;
    }
  }
  
  return 0;
}

@end
