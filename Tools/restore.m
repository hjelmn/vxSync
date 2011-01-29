
/* (-*- objc -*-)
 * vxSync: restore.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include <stdlib.h>
#include <stdio.h>

#include "VXSync.h"
#include "vxPhone.h"

static inline NSDictionary *defaultFolderAttributes (void) {
  return [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0700] forKey: NSFilePosixPermissions];
}

void restore (vxPhone *phone, NSString *from) {
  char *temp_location = tempnam ("/tmp", "vxsync");
  NSString *tempLocation = [NSString stringWithUTF8String: temp_location];
  NSString *file;
  NSError *error = nil;
  NSDirectoryEnumerator *dirEnum;
  NSFileManager *fileManager = [NSFileManager defaultManager];
  BOOL isDir;
  int ret, stat_loc, fileCount, restoreCount;
  unsigned char buffer[2048];

  do {
    /* need to clear the persistent domain for this phone */
    NSMutableDictionary *rootObject = [[[[NSUserDefaults standardUserDefaults] persistentDomainForName: @"com.enansoft.vxSync.LGPBEntryFile"] mutableCopy] autorelease];
    
    free (temp_location);
    
    if (![phone efs])
      break;
    
    [rootObject removeObjectForKey: [phone identifier]];
    [[NSUserDefaults standardUserDefaults] setPersistentDomain: rootObject forName: @"com.enansoft.vxSync.LGPBEntryFile"];
    
    ret = [fileManager createDirectoryAtPath: tempLocation withIntermediateDirectories: YES attributes: defaultFolderAttributes() error: &error];
    if (ret == NO) {
      vxSync_log3(VXSYNC_LOG_ERROR, @"could not create temporary directory: %s. error = %s\n", NS2CH(tempLocation), NS2CH(error));
      break;
    }
    
    ret = fork ();
    if (ret == 0) {
      chdir ([tempLocation UTF8String]);
      execl ("/usr/bin/tar", "/usr/bin/tar", "xfj", [from UTF8String], NULL);
    }
    
    waitpid (ret, &stat_loc, 0);

    restoreCount = 0;
    fileCount = 0;
    
    dirEnum = [fileManager enumeratorAtPath: tempLocation];
    while (file = [dirEnum nextObject]) {
      NSString *localPath = [tempLocation stringByAppendingPathComponent: file];
      (void)[fileManager fileExistsAtPath: localPath isDirectory: &isDir];

      printf ("Restoring: %s\n", [file UTF8String]);

      if (isDir == NO) {
        int fd, fdPhone;
        
        vxSync_log3(VXSYNC_LOG_INFO, @"restoring file: phone:%s\n", NS2CH(file));
        
        fileCount ++;
        fd = open ([localPath UTF8String], O_RDONLY);
        if (fd < 0) {
          vxSync_log3(VXSYNC_LOG_WARNING, @"could not open %s for reading. reason: %s\n", NS2CH(localPath), strerror(errno));
          continue;
        }
        
        fdPhone = [[phone efs] open: file withFlags: O_CREAT | O_WRONLY | O_TRUNC, 0644];
        if (fdPhone < 0) {
          vxSync_log3(VXSYNC_LOG_WARNING, @"could not open phone:%s for writing. reason: %s\n", NS2CH(file), strerror(errno));
          close (fd);
          continue;
        }
        
        while ((ret = read (fd, buffer, 2048)) > 0) {
          int writeRet = [[phone efs] write: fdPhone from: buffer count: ret];
          if (writeRet != ret)
            vxSync_log3(VXSYNC_LOG_ERROR, @"writing to phone:%s. wrote %i/%i bytes. error: %s\n", file, writeRet < 0 ? 0 : writeRet, ret, strerror(errno));
        }
        
        restoreCount++;
        
        [[phone efs] close: fdPhone];
        close (fd);
      } else {
        vxSync_log3(VXSYNC_LOG_INFO, @"restoring directory: phone:%s\n", NS2CH(file));
        [[phone efs] mkdir: file withMode: 0755];
      }
    }
    
    [fileManager removeFileAtPath: tempLocation handler: nil];
    [[phone efs] setRequiresReboot: YES];
    [[phone efs] reboot];
  } while (0);
}

void usage (void) {
  printf ("Usage:\n");
  printf (" vxRestore <phone identifier> <source> <log level>\n");
  exit (3);
}

mach_port_t masterPort;

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  int log_fd = -1;
  
  masterPort = IO_OBJECT_NULL;
  
  if (argc < 4)
    usage ();
    
  if (argc > 4)
    log_fd = strtol(argv[4], NULL, 10);
  
  setbuf(stdout, NULL);
  
  [vxSyncLogger setDefaultLogger: [vxSyncLogger loggerWithLevel: strtol (argv[3], NULL, 10) logFd: log_fd progName: @"vxSyncDevice"]];
  
  NSString *source = [NSString stringWithUTF8String: argv[2]];
  
  vxPhone *phone = [vxPhone phoneWithIdentifier: [NSString stringWithUTF8String: argv[1]]];
  
  if (!phone)
    return 1;
  
  restore (phone, source);

  [phone cleanup];

  [vxSyncLogger setDefaultLogger: nil];

  [releasePool release];
  
  return 0;
}
