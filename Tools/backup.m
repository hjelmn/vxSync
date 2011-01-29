/* (-*- objc -*-)
 * vxSync: backup.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "VXSync.h"
#include "vxPhone.h"

static inline NSDictionary *defaultFolderAttributes (void) {
  return [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0700] forKey: NSFilePosixPermissions];
}

int copyDir (NSString *src, NSString *dst, vxPhone *phone, int *backedp, int *countp) {
  DIR *foo;
  struct dirent *entry;
  struct stat statinfo;
  int fd, dfd, ret;
  unsigned char buffer[2048];
  NSString *destination;
  NSError *error = nil;
  NSFileManager *fileManager = [NSFileManager defaultManager];  
  NSMutableArray *dirsToBackup = [NSMutableArray array];
  
  ret = [[phone efs] stat: src to: &statinfo];
  if (ret < 0) {
    vxSync_log3(VXSYNC_LOG_INFO, @"could not stat phone:%s: %s\n", NS2CH(src), strerror(errno));
    return -1;
  }
  
  destination = [dst stringByAppendingPathComponent: src];
  
  if ([fileManager createDirectoryAtPath: destination withIntermediateDirectories: YES attributes: defaultFolderAttributes () error: &error] == NO) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not create temporary directory: %s. error = %s\n", NS2CH(destination), NS2CH(error));
    return -1;
  }
  
  ret = 0;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"creating backup of directory: phone:%s ------> %s\n", NS2CH(src), NS2CH(destination));
  
  foo = [[phone efs] opendir: src];
  while (entry = [[phone efs] readdir: foo]) {
    NSString *dirItem = [NSString stringWithUTF8String: entry->d_name];
    NSString *nextSrc = [src stringByAppendingPathComponent: dirItem];
    NSString *nextDst = [destination stringByAppendingPathComponent: dirItem];
    
    vxSync_log3(VXSYNC_LOG_INFO, @"file: %s\n", entry->d_name);
    printf ("Backing up file: %s\n", [nextSrc UTF8String]);
    
    /* ignore special directories (".", "..") */
    if (strcmp (".", entry->d_name) == 0 || strcmp ("..", entry->d_name) == 0)
      continue;
    
    if (entry->d_type != DT_DIR) {
      if ([[phone efs] stat: nextSrc to: &statinfo] < 0)
        continue;

      fd = [[phone efs] open: nextSrc withFlags: O_RDONLY];
      dfd = open ([nextDst UTF8String], O_WRONLY | O_CREAT, statinfo.st_mode | 0600);
      if (dfd < 0)
        vxSync_log3(VXSYNC_LOG_ERROR, @"error opening %s for reading. reason: %s\n", NS2CH(nextDst), strerror (errno));
      
      if (fd > -1 && dfd > -1) {
        /* loop through the file data */
        while (ret = [[phone efs] read: fd to: buffer count: 1024])
          write (dfd, buffer, ret);
        (*backedp) ++;
      }
      (*countp) ++;
      
      if (dfd > -1)
        close (dfd);
      
      if (fd > -1)
        [[phone efs] close: fd];
    } else
      [dirsToBackup addObject: nextSrc];
  }
  
  for (id directory in dirsToBackup)
    copyDir (directory, dst, phone, backedp, countp);
    
  [[phone efs] closedir: foo];
  
  return ret;
}


void backup (NSString *destination, vxPhone *phone) {
  char *temp_location = strdup ("/tmp/vxsync.XXXX");
  NSString *tempLocation;
  NSFileManager *fileManager = [NSFileManager defaultManager];
  int ret, stat_loc, backedup, count;
  BOOL result;
  
  if (![phone efs])
  /* display an error message */
    return;
  
  if (!mkdtemp (temp_location))
  /* display an error message */
    return;
  
  tempLocation = [NSString stringWithUTF8String: temp_location];
  
  free (temp_location);
  
  backedup = count = 0;
  
  ret = copyDir (@"pim", tempLocation, phone, &backedup, &count);
  ret = copyDir (@"sch", tempLocation, phone, &backedup, &count) || ret;
  if ([[phone efs] stat: @"set_as_pic_id_dir" to: nil] == 0)
    ret = copyDir (@"set_as_pic_id_dir", tempLocation, phone, &backedup, &count) || ret;

  printf ("Backed up %d files.\n", backedup);
  
  ret = fork ();
  if (ret == 0) {
    chdir ([tempLocation UTF8String]);
    execl ("/usr/bin/tar", "/usr/bin/tar", "cfj", [destination UTF8String], "pim", "sch", NULL);
  } else
    waitpid (ret, &stat_loc, 0);
    
    result = [fileManager removeFileAtPath: tempLocation handler: nil];
    vxSync_log3(VXSYNC_LOG_INFO, @"removing temporary directory %s. result = %i\n", NS2CH(tempLocation), result);
}

void usage (void) {
  printf ("Usage:\n");
  printf (" vxBackup <phone identifier> <destination> <log level>\n");
  exit (3);
}

mach_port_t masterPort;

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  int log_fd = -1;
  
  masterPort = IO_OBJECT_NULL;
  
  if (argc < 4)
    usage ();
  else if (argc > 4)
    log_fd = strtol(argv[4], NULL, 10);
  
  setbuf(stdout, NULL);
  
  [vxSyncLogger setDefaultLogger: [vxSyncLogger loggerWithLevel: strtol (argv[3], NULL, 10) logFd: log_fd progName: @"vxBackup"]];
  
  NSString *destination = [NSString stringWithUTF8String: argv[2]];

  vxPhone *phone = [vxPhone phoneWithIdentifier: [NSString stringWithUTF8String: argv[1]]];
  
  if (!phone)
    return 1;
  
  backup (destination, phone);
  
  [phone cleanup];

  [vxSyncLogger setDefaultLogger: nil];

  [releasePool release];
  
  return 0;
}