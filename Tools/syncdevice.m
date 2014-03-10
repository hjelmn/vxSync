/* (-*- objc -*-)
 * vxSync: syncdevice.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.5
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include <stdlib.h>
#include <stdio.h>
#include <Cocoa/Cocoa.h>

#include "VXSync.h"
#include "BREWefs.h"
#include "VXSyncDataSource.h"
#include "vxSyncCalendarFilter.h"
#include "vxSyncGroupFilter.h"

int setupClientSyncFilters (VXSyncDataSource *dataSource, vxPhone *phone) {
  @try {
    ISyncClient *myClient = [[ISyncManager sharedManager] registerClientWithIdentifier: [dataSource clientIdentifier] descriptionFilePath: [dataSource clientDescriptionPath]];
    NSMutableArray *filters = [NSMutableArray array];
    
    /* do not set up any filters when set to overwrite the computer or the mode is disabled */
    if ([phone getOption: @"calendar.sync"] && [[phone getOption:@"calendar.mode"] intValue] != VXSYNC_MODE_PHONE_OW) {
      NSArray *syncCalendars = [phone getOption: @"calendar.list"];
      
      if (![[phone getOption: @"calendar.syncAll"] boolValue])
        syncCalendars = [syncCalendars filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"enabled == YES"]];
      
      syncCalendars = [syncCalendars mapSelector: @selector(objectForKey:) withObject: @"title"];

      id filter = [vxSyncCalendarFilter filter];
      
      [filter setCalendarTitles: syncCalendars];
      [filter setClientIdentifier: [dataSource clientIdentifier]];
      
      [filters addObject: filter];
    }
    
    /* do not set up any filters when set to overwrite the computer or the mode is disabled */
    if ([[phone getOption: @"contacts.sync"] boolValue] && [[phone getOption:@"contacts.mode"] intValue] != VXSYNC_MODE_PHONE_OW) {
      NSArray *syncGroups = [phone getOption: @"contacts.list"];
      
      if (![[phone getOption: @"contacts.syncAll"] boolValue])
        syncGroups = [syncGroups filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"enabled == YES"]];
      
      syncGroups = [syncGroups mapSelector: @selector(objectForKey:) withObject: @"name"];
      
      id filter = [vxSyncGroupFilter filter];
      [filter setGroupNames: syncGroups];
      [filter setClientIdentifier: [dataSource clientIdentifier]];
      [filter setSyncAllGroups: [[phone getOption: @"contacts.syncAll"] boolValue]];
      [filter setSyncOnlyWithPhoneNumbers: [[phone getOption: @"contacts.syncOnlyWithPhoneNumbers"] boolValue]];

      [filters addObject: filter];
    }
    
    [myClient setFilters: filters];
  } @catch (NSException *e) {
    printf ("An exception occurred: %s\n", [[e description] UTF8String]);
    return -1;
  }
  
  return 0;
}

int syncDevice (vxPhone *phone) {
  VXSyncDataSource *syncClient;
  ISyncSessionDriver *syncDriver;
  int ret;
  
  if (![[ISyncManager sharedManager] isEnabled]) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"syncing is disabled in iSync\n");
    return 1;
  }
  
  printf ("Syncing...\n");
  
  do {
    syncClient = [[VXSyncDataSource dataSourceWithPhone: phone] retain];
    if (!syncClient)
      return 1;
    
    ret = setupClientSyncFilters(syncClient, phone);
    if (ret != 0)
      return ret;

    @try {
      /* create the sync session driver */
      syncDriver = [ISyncSessionDriver sessionDriverWithDataSource: syncClient];
      [syncDriver setDelegate: syncClient];
      
      [syncClient setSessionDriver: syncDriver];
      
      /* sync */
      BOOL result = [syncDriver sync];
      vxSync_log3(VXSYNC_LOG_INFO, @"finished phase 1, on to phase 2\n");
      if (result && [syncClient needsTwoPhaseSync]) {
        [syncClient setPhase: 2];

        /* reset the sync driver */
        syncDriver = [ISyncSessionDriver sessionDriverWithDataSource: syncClient];
        [syncDriver setDelegate: syncClient];

        /* run phase 2 of the sync */
        result = [syncDriver sync];
      }
      
      if (!result) {
        vxSync_log3(VXSYNC_LOG_ERROR, @"an error occurred while syncing: %s\n", NS2CH([syncDriver lastError]));
        vxSync_log3(VXSYNC_LOG_ERROR, @"%s\n", NS2CH([[syncDriver lastError] userInfo]));
        
        printf ("Error! See error log.\n");

        return 2;
      } else {
        
        if ([[phone efs] requiresReboot]) {
          printf ("Sucess! Rebooting phone...\n");
          [[phone efs] reboot];
        } else
          printf ("Success!\n");
      }
    } @catch (NSException *e) {
      vxSync_log3(VXSYNC_LOG_ERROR, @"caught exception: %s\n", NS2CH(e));

      if( [e respondsToSelector: @selector(callStackSymbols)] ) {
        id (*callStackSymbols)(id, SEL) = (id (*)(id, SEL))[e methodForSelector: @selector(callStackSymbols)];
        vxSync_log3(VXSYNC_LOG_ERROR, @"Backtrack = %s\n", NS2CH(callStackSymbols (e, @selector(callStackSymbols))));
      } else {
        vxSync_log3(VXSYNC_LOG_ERROR, @"Return = %s\n", NS2CH([e callStackReturnAddresses]));
      }

      printf ("Error! Check console for more information.\n");
      
      return 3;
    }
  } while (0);
  
  return 0;
}

#if 0
void cleanupLocalStore (void) {
  NSDictionary *rootObject = [[NSUserDefaults standardUserDefaults] persistentDomainForName: kBundleDomain];
  NSMutableArray *files = [NSMutableArray array];

  if (rootObject && [rootObject objectForKey: @"Phones"]) {
    for (id phone in [rootObject objectForKey: @"Phones"]) {
      NSString *domain = [NSString stringWithFormat: @"com.enansoft.vxSync.%@", [phone objectForKey: @"Unique ID"]];
      NSDictionary *phonePS = [[NSUserDefaults standardUserDefaults] persistentDomainForName: domain];
      for (id records in [phonePS allObjects]) {
        for (id record in [records allObjects]) {
          if ([record objectForKey: VXKeyPicturePath]) {
            [files addObject: [record objectForKey: VXKeyPicturePath]];
          }
        }
      }
    }
  }
  
  NSArray *files [[NSFileManager defaultManager] directoryContentsAtPath: [NSHomeDirectory() stringByAppendingString: PersistentStoreDir]];
  
  printf ("files = %s\n", [[files description] UTF8String]);
}
#endif
void usage (int argc) {
  fprintf (stderr, "Usage:\n");
  fprintf (stderr, " vxSyncDevice <phone identifier> <log level>\n");
  exit (3);
}

mach_port_t masterPort;

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  int log_fd = -1;
  
  masterPort = IO_OBJECT_NULL;

  if (argc < 3)
    usage (argc);
  
  if (argc > 3)
    log_fd = strtol(argv[3], NULL, 10);
  
  setbuf(stdout, NULL);
  
  [vxSyncLogger setDefaultLogger: [vxSyncLogger loggerWithLevel: strtol (argv[2], NULL, 10) logFd: log_fd progName: @"vxSyncDevice"]];

  vxPhone *phone = [vxPhone phoneWithIdentifier: [NSString stringWithUTF8String: argv[1]]];

  if (!phone) {
    printf ("Could not connect to device.\n");
    return 1;
  }
  
  syncDevice (phone);

  [phone cleanup];
  
  [vxSyncLogger setDefaultLogger: nil];
  
  [releasePool release];
  
  return 0;
}
