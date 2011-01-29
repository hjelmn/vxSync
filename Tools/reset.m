/* (-*- objc -*-)
 * vxSync: backup.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "VXSync.h"
#include "vxPhone.h"

mach_port_t masterPort;

void send_reset (vxPhone *phone, unsigned char cmd) {
  unsigned char bytes[1024];

  bytes[0] = 0xf1;
  bytes[1] = cmd;

  [[phone efs] send_recv_message: bytes sendLength: 4 sendBufferSize: 1024 recvTo: bytes recvLength: 1024];

}

int wipe (vxPhone *phone) {
  /* remove the calendar file since a reset won't delete it */
  [[phone efs] unlink: @"sch/isynccalendars.plist"];
  
  /* clear call logs */
  printf ("Clearing call logs...\n");
  send_reset (phone, 0x21);

  /* clear phonebook */
  printf ("Clearing phonebook...\n");
  send_reset (phone, 0x2f);

  /* clear calendar */
  printf ("Clearing phone calendar...\n");
  send_reset (phone, 0x35);

  /* factory reset */
  printf ("Factory reset...\n");
  send_reset (phone, 0x49);

  printf ("Rebooting phone...\n");
  usleep (500000);
  
  printf ("Success\n");
  
  return 0;
}

void usage (void) {
  printf ("Usage:\n");
  printf (" vxReset <phone identifier> <log level>\n");
  exit (3);
}

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  int log_fd = -1;
  
  masterPort = IO_OBJECT_NULL;
  
  if (argc < 3)
    usage ();
  
  if (argc > 3)
    log_fd = strtol(argv[3], NULL, 10);

  setbuf(stdout, NULL);

  [vxSyncLogger setDefaultLogger: [vxSyncLogger loggerWithLevel: strtol (argv[2], NULL, 10) logFd: log_fd progName: @"vxReset"]];

  vxPhone *phone = [vxPhone phoneWithIdentifier: [NSString stringWithUTF8String: argv[1]]];
  
  if (!phone)
    return 1;
  
  wipe (phone);
    
  [phone cleanup];

  [vxSyncLogger setDefaultLogger: nil];

  [releasePool release];
  
  return 0;
}
