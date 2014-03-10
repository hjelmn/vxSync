/* (-*- objc -*-)
 * vxSync: vxSyncAppDelegate.m
 * (C) 2009-2011 Nathan Hjelm
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

#import "vxSyncAppDelegate.h"
#import "vxAvailableTransformer.h"
#import "vxPhone.h"

#import <CalendarStore/CalendarStore.h>
#include <mach/mach_port.h>

mach_port_t  masterPort = 0; /* master port */

NSDictionary *defaultFolderAttributes (void) {
  return [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0700] forKey: NSFilePosixPermissions];
}

NSString *applicationSupportPath (void) {
  return [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/vxSync"];
}

NSString *backupStorePath (void) {
  return [applicationSupportPath() stringByAppendingPathComponent: @"Backups"];
}

id find_object_with_key (NSDictionaryController *controller, NSString *key) {
  NSArray *aos = [controller arrangedObjects];
  
  for (id ao in aos)
    if ([[ao key] isEqualToString: key])
      return ao;
  
  return nil;
}

void set_disconnected (NSMutableDictionary *device) {
  [device setObject: [NSMutableArray array] forKey: @"locations"];
  [device removeObjectForKey: @"busy"];
  [device removeObjectForKey: @"status"];
  [device setObject: [NSNumber numberWithBool: NO] forKey: @"available"];
  [device setObject: @"Not connected" forKey: @"connections"];
}

void convert_old_to_new_path (NSMutableDictionary *dict, NSString *oldKey, NSString *newKeyPath) {
  if ([dict objectForKey: oldKey]) {
    [dict setValue: [dict objectForKey: oldKey] forKeyPath: newKeyPath];
    [dict removeObjectForKey: oldKey];
  }
}

void add_value_to_controller (NSDictionaryController *controller, NSObject *value, NSString *key) {
  id newObject = [controller newObject];
  [newObject setValue: value];
  [newObject setKey: key];
  [controller addObject: newObject];
}

@interface vxSyncAppDelegate (hidden)
- (NSNumber *) logLevel;
- (NSBundle *) bundle;
- (void) readSyncServerPreferences;
@end

@implementation vxSyncAppDelegate

@synthesize window, defaultsController, fKnownDevicesController, fUnknownDevices, isBusy, preferencePanel;
@synthesize progIndicator, calendarController, groupController, updateIndicator, btScanIndicator;
@synthesize btScanStatus, fUnknownDevicesController, addView, actionStatus, errorPanel, errorText;
@synthesize logDataController, logTableView, logTableColumn, disableSyncAlerts, syncAlertIndex;

- (void) applicationWillFinishLaunching:(NSNotification *)aNotification {
  [self defaultsInitialize];
}

- (void) awakeFromNib {
  /* interface builder 3.2 can set this property now but produces a warning for 10.5 targets */
  [window setContentBorderThickness:26.0 forEdge:NSMinYEdge];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// Insert code here to initialize your application  
  NSError *error = nil;
  
  NSFileManager *fileManager = [NSFileManager defaultManager];

  [vxSyncLogger setDefaultLogger: [vxSyncLogger loggerWithLevel: [[self logLevel] integerValue] controller: logDataController progName: @"vxSync"]];
  vxSync_log3(VXSYNC_LOG_INFO, @"initializing vxSync...\n");
  
  [self setBusy: NO animation: YES];
  
  [self setFUnknownDevices: [NSMutableDictionary dictionary]];
  
  /* Create Application support directory */
  [fileManager createDirectoryAtPath: applicationSupportPath() withIntermediateDirectories: YES attributes: defaultFolderAttributes () error: &error];
  [fileManager createDirectoryAtPath: backupStorePath() withIntermediateDirectories: YES attributes: defaultFolderAttributes () error: &error];  
  
  [self updateGroups: nil];
  [self updateCalendars: nil];
  
  for (id item in [fKnownDevicesController arrangedObjects]) {
    NSMutableDictionary *device = [[[item value] mutableCopy] autorelease];

    set_disconnected(device);
    NSArray *foo = [[device objectForKey: @"imagePath"] componentsSeparatedByString: @"PlugIns"];
    if ([foo count])
      [device setObject: [[[self bundle] builtInPlugInsPath] stringByAppendingFormat: [foo objectAtIndex: 1]] forKey: @"imagePath"];
    
    [item setValue: device];
  }  
  
  [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(deviceArrived:) name: @"USBDevicePlug" object: nil];
  [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(deviceLeft:) name: @"USBDeviceUnplug" object: nil];

  [[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(updateCalendars:)
                                               name: CalCalendarsChangedExternallyNotification
                                             object: [CalCalendarStore defaultCalendarStore]];
  
  [[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(updateGroups:)
                                               name: kABDatabaseChangedExternallyNotification
                                             object: [ABAddressBook sharedAddressBook]];
  
  [self readSyncServerPreferences];
  
  /* create a master port to talk to IOKit */
  IOMasterPort (IO_OBJECT_NULL, &masterPort);

  [self initBluetooth];
  (void *)[IOUSBPhone scanDevices];
  [IOUSBPhone startNotifications];
}

- (void) dealloc {
  [IOUSBPhone stopNotifications];
  [self finalizeBluetooth];

  [self setFUnknownDevices: nil];
  
  if (masterPort) {
    mach_port_deallocate (mach_task_self(), masterPort);
    masterPort = IO_OBJECT_NULL;
  }

  [vxSyncLogger setDefaultLogger: nil];

  /* no longer need to listen for notifications */
  [[NSNotificationCenter defaultCenter] removeObserver: self];

  [super dealloc];
}

- (NSString*) versionString {
  NSString *versionShortString = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
  NSString *bundleVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"];
  return [NSString stringWithFormat: @"%@ (%@)", versionShortString, bundleVersion];
}

- (IBAction) doDonate: (id) sender {
  [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=7955408"]];
}

- (int) setBusy: (bool) value animation: (bool) startStopAnimation {
  if (value) {
    int tries;
  
    for (tries = 0 ; isBusy && tries < 10 ; tries++) usleep (1000);
    if (isBusy)
      return -1;
  
    [self setIsBusy: YES];

    if (startStopAnimation)
      [progIndicator startAnimation: self];
  } else {
    [self setIsBusy: NO];  

    if (startStopAnimation)
      [progIndicator stopAnimation: self];
  }
  
  return 0;
}

/* update calendars and groups */
- (void) updateCalendars: (id) sender {
  NSArray *_calendars = [[CalCalendarStore defaultCalendarStore] calendars];
  NSArray *calendarUIDs = [_calendars mapSelector: @selector(uid)];

  for (id identifier in [fKnownDevicesController content]) {
    NSMutableDictionary *device = [find_object_with_key (fKnownDevicesController, identifier) value];
    NSMutableArray *newCalendars = [device mutableArrayValueForKeyPath: @"calendar.list"];
    id newEventCalendar = nil;

    [newCalendars filterUsingPredicate: [NSPredicate predicateWithFormat: @"identifier IN %@", calendarUIDs]];

    for (id calendar in _calendars) {
      NSArray *matching = [newCalendars filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"identifier == %@", [calendar uid]]];
      NSMutableDictionary *updCalendar = nil;

      if ([matching count]) {        
        updCalendar = [matching objectAtIndex: 0];

        if ([[updCalendar objectForKey: @"title"] isEqualToString: [device valueForKeyPath: @"calendar.storeIn"]])
          newEventCalendar = updCalendar;
      } else {
        updCalendar = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: YES], @"enabled", nil];
        [newCalendars addObject: updCalendar];
      }

      [updCalendar setObject: [calendar title] forKey: @"title"];
      [updCalendar setObject: [calendar uid] forKey: @"identifier"];

      if (![calendar isEditable])
        [updCalendar removeObjectForKey: @"readwrite"];
      else
        [updCalendar setObject: [NSNumber numberWithBool: YES] forKey: @"readwrite"];
    }

    if (!newEventCalendar)
      for (id calendar in newCalendars)
        if ([[calendar objectForKey: @"readwrite"] boolValue]) {
          newEventCalendar = calendar;
          break;
        }

    [device setValue: [newEventCalendar objectForKey: @"title"] forKeyPath: @"calendar.storeIn"];
  }
}

- (void) updateGroups: (id) sender {
  NSArray *_groups = [[ABAddressBook sharedAddressBook] groups];
  NSArray *groupUIDs = [_groups mapSelector: @selector(uniqueId)];
  
  for (id device in [fKnownDevicesController arrangedObjects]) {
    NSMutableArray *newGroups = [[device value] mutableArrayValueForKeyPath: @"contacts.list"];

    [newGroups filterUsingPredicate: [NSPredicate predicateWithFormat: @"identifier IN %@", groupUIDs]];

    for (id group in _groups) {
      NSArray *matching = [newGroups filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"identifier == %@", [group uniqueId]]];
      NSMutableDictionary *updGroup = [matching count] ? [matching objectAtIndex: 0] :
                                                         [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: YES], @"enabled", nil];

      [updGroup setObject: [group uniqueId] forKey: @"identifier"];
      [updGroup setObject: [group valueForProperty: @"name"] forKey: @"name"];
      
      if (![matching count]) [newGroups addObject: updGroup];
    }
  }
}


/* XXX -- todo -- move me */
- (void) writePreferences {
  [defaultsController commitEditing];
}


- (void) setPropertyForPhone: (NSDictionary *) properties {
  id phone = [properties objectForKey: @"phone"];
  NSMutableDictionary *updatedDictionary = [[[phone value] mutableCopy] autorelease];

  NSString *keyPath    = [properties objectForKey: @"keyPath"];
  NSString *value      = [properties objectForKey: @"value"];
  
  [updatedDictionary setValue: value forKeyPath: keyPath];
  
  [phone setValue: updatedDictionary];
}

/* XXX -- todo -- move me */
- (void) setStatus: (NSString *) _status forDeviceWithIdentifier: (NSString *) _identifier {
  id phone = find_object_with_key (fKnownDevicesController, _identifier);
  
  [self performSelectorOnMainThread: @selector(setPropertyForPhone:) withObject: [NSDictionary dictionaryWithObjectsAndKeys: phone, @"phone",
                                                                                  @"status", @"keyPath",
                                                                                  _status, @"value", nil]
                      waitUntilDone: YES];
  
  if (_status)
  /* always log status changes */
    [[vxSyncLogger defaultLogger] addMessage: [NSString stringWithFormat: @"%@: %@", [phone valueForKeyPath: @"value.bluetooth.name"], _status]];
}

- (void) setLastSync: (NSDate *) date forDeviceWithIdentifier: (NSString *) _identifier {
  id phone = find_object_with_key (fKnownDevicesController, _identifier);
  
  [self performSelectorOnMainThread: @selector(setPropertyForPhone:) withObject: [NSDictionary dictionaryWithObjectsAndKeys: phone, @"phone",
                                                                                  @"LastSync", @"keyPath",
                                                                                  date, @"value", nil]
                      waitUntilDone: YES];
}

- (BOOL) setBusy: (BOOL) _busy forDeviceWithIdentifier: (NSString *) _identifier {  
  @try {
    id phone = find_object_with_key (fKnownDevicesController, _identifier);

    if (_busy) {
      if ([[phone valueForKeyPath: @"value.busy"] boolValue] || ![[phone valueForKeyPath: @"value.available"] boolValue]) {
        vxSync_log3(VXSYNC_LOG_INFO, @"phone is busy\n");
        return NO;
      }
    }
    
    [self performSelectorOnMainThread: @selector(setPropertyForPhone:) withObject: [NSDictionary dictionaryWithObjectsAndKeys: phone, @"phone",
                                                                                      @"busy", @"keyPath",
                                                                                    [NSNumber numberWithBool: _busy], @"value", nil]
                        waitUntilDone: YES];
  } @catch (NSException *e) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"got exception: %s\n", NS2CH(e));
    return NO;
  }

  return YES;
}

- (NSString *) identifierForSelectedPhone {
  id selected = [[fKnownDevicesController selection] valueForKeyPath: @"self"];
  return [selected key];
}

- (int) forPhoneWithIdentifier: (NSString *) identifier runHelper: (id) helperPath, ... {
  char *helperPathCString, *args[20];
  va_list vargs;
  int childStatus, argno, filedes[2], efiledes[2];
  pid_t pid;

  vxSync_log3(VXSYNC_LOG_INFO, @"running tool %s...\n", NS2CH(helperPath));
  
  memset (args, 0, 20 * sizeof (char *));

  helperPathCString = strdup ((char *)[[helperPath description] UTF8String]);
  args[0]           = strdup ((char *)[[helperPath description] UTF8String]);
  
  va_start (vargs, helperPath);
  for (argno = 1 ; argno < 20 ; argno++) {
    char *arg = (char *)[[va_arg (vargs, id) description] UTF8String];
    if (!arg)
      break;
    
    args[argno] = strdup (arg);
  }
  va_end (vargs);
  
  pipe (filedes);
  pipe (efiledes);
  pid = fork ();
  if (0 == pid) {
    char baz[20];

    dup2 (filedes[1], 1);

    close (filedes[0]);
    close (filedes[1]);
    close (efiledes[0]);
    
    snprintf (baz, 20, "%d", efiledes[1]);
    args[argno++] = baz;
    
    execv (helperPathCString, args);

    exit (1); /* exec failed */
  }

  /* free argument list -- not needed for the parent */
  for (argno = 0 ; argno < 20 ; argno++) {
    if (args[argno])
      free (args[argno]);
  }

  free (helperPathCString);

  /* read messages from the child */
  close (filedes[1]);
  close (efiledes[1]);

  NSDictionary *threadData = [NSDictionary dictionaryWithObjectsAndKeys: identifier, @"identifier", [NSNumber numberWithInt: filedes[0]], @"fileDescriptor", nil];
  
  [NSThread detachNewThreadSelector: @selector(readToolStdin:) toTarget: self withObject: (id)threadData];

  threadData = [NSDictionary dictionaryWithObjectsAndKeys: identifier, @"identifier", [NSNumber numberWithInt: efiledes[0]], @"fileDescriptor", nil];
  [NSThread detachNewThreadSelector: @selector(readToolStderr:) toTarget: self withObject: (id)threadData];
  
  /* wait for child to finish */
  waitpid (pid, &childStatus, 0);

  vxSync_log3(childStatus ? VXSYNC_LOG_ERROR : VXSYNC_LOG_INFO, @"helper returned code = %i\n", childStatus);

  if (childStatus)
    [self setStatus: @"An error occurred. Check the error log" forDeviceWithIdentifier: identifier];
  
  usleep (3000000);
  [self setStatus: nil forDeviceWithIdentifier: identifier];
  
  return childStatus;
}

- (void) readToolStdin: (id) object {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSString *identifier = [object objectForKey: @"identifier"];
  int fd = [[object objectForKey: @"fileDescriptor"] intValue];
  FILE *message_fh = fdopen(fd, "r");
  char messageBuffer[512];

  memset (messageBuffer, 0, 512);
  while (fgets (messageBuffer, 255, message_fh)) {
    if ('\n' == messageBuffer[strlen(messageBuffer) - 1])
      messageBuffer[strlen(messageBuffer) - 1] = '\0';
    [self setStatus: [NSString stringWithUTF8String: messageBuffer] forDeviceWithIdentifier: identifier];
  }
  
  fclose(message_fh);
  
  [releasePool release];
}

- (void) readToolStderr: (id) object {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
//  NSString *identifier = [object objectForKey: @"identifier"];
  int fd = [[object objectForKey: @"fileDescriptor"] intValue];
  FILE *message_fh = fdopen(fd, "r");
  size_t buffer_len = 512;
  char *messageBuffer;

  messageBuffer = malloc(buffer_len);
  if (!messageBuffer) {
    fclose(message_fh);
    [releasePool release];

    return;
  }
  
  do {
    NSMutableString *message = [NSMutableString string];

    do {
      char *tmp2 = fgets(messageBuffer, buffer_len, message_fh);
      int read_len;
      
      if (!tmp2)
        break;
      
      read_len = strlen (messageBuffer);
      
      if (!read_len || messageBuffer[0] == '\n') {
        break;
      }
      
      [message appendFormat: @"%s", messageBuffer];
    } while (1);
    
    if ([message length])    
      [[vxSyncLogger defaultLogger] addMessage: message];
  } while (!feof(message_fh));

  free (messageBuffer);
  
  fclose(message_fh);
    
  [releasePool release];
}

- (NSNumber *) logLevel {
  return [[defaultsController values] valueForKey: @"LogLevel"];
}

- (NSBundle *) bundle {
  return [NSBundle mainBundle];
}

- (void) syncThread: (id) sender {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSString *deviceIdentifier = [self identifierForSelectedPhone];
  int ret;
  
  if (![[ISyncManager sharedManager] isEnabled]) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"syncing is disabled in iSync\n");

    NSAlert *disabledAlert = [NSAlert alertWithMessageText: @"Syncing is disabled in iSync" defaultButton: @"Ok" alternateButton: nil otherButton: nil informativeTextWithFormat: @"Turn syncing on in iSync before attempting to sync"];
    [disabledAlert beginSheetModalForWindow: window modalDelegate: nil didEndSelector: nil contextInfo: nil];
    [releasePool release];
    return;
  }
  
  if ([self setBusy: YES forDeviceWithIdentifier: deviceIdentifier]) {
    vxSync_log3(VXSYNC_LOG_INFO, @"attempting to sync\n");
    
    /* set UI status */
    [self setStatus: @"Syncing" forDeviceWithIdentifier: deviceIdentifier];
    
    /* ensure tool has same view of options */
    [self writePreferences];  
    
    ret = [self forPhoneWithIdentifier: deviceIdentifier runHelper: [[[self bundle] resourcePath] stringByAppendingFormat: @"/vxSyncDevice"],
           deviceIdentifier, [[self logLevel] description], nil];
    if (!ret)
      [self setLastSync: [NSDate date] forDeviceWithIdentifier: deviceIdentifier];

    [self setBusy: NO forDeviceWithIdentifier: deviceIdentifier];
  }
  
  [releasePool release];
}

- (void) endSyncAlert: (NSAlert *) alert returnCode: (int) returnCode contextInfo: (int *) contextInfo {
  if (0 == returnCode) { /* default button */
    [NSThread detachNewThreadSelector: @selector(syncThread:) toTarget: self withObject: nil];
  } /* else ignore */
}

- (IBAction) sync: (id) sender {
  [[NSUserDefaults standardUserDefaults] synchronize];

  id phone = [[fKnownDevicesController selection] valueForKeyPath: @"self.value"];

  if (([[phone valueForKeyPath: @"calendar.sync"] boolValue] && VXSYNC_MODE_PHONE_OW == [[phone valueForKeyPath: @"calendar.mode"] intValue]) ||
      ([[phone valueForKeyPath: @"contacts.sync"] boolValue] && VXSYNC_MODE_PHONE_OW == [[phone valueForKeyPath: @"contacts.mode"] intValue]) ||
      ([[phone valueForKeyPath: @"notes.sync"] boolValue] && VXSYNC_MODE_PHONE_OW == [[phone valueForKeyPath: @"notes.mode"] intValue])) {
    [[NSAlert alertWithMessageText: @"One or more data sources are set to overwrite the computer. Are you sure you want to replace data on this computer with data the phone?" defaultButton: @"Cancel" alternateButton: @"Sync" otherButton: nil informativeTextWithFormat: @"This action can not be undone"] beginSheetModalForWindow: window modalDelegate: self didEndSelector: @selector(endSyncAlert:returnCode:contextInfo:) contextInfo: nil];
    return;
  } else
    [NSThread detachNewThreadSelector: @selector(syncThread:) toTarget: self withObject: nil];
}

- (void) backupThread: (id) sender {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  id selected = [[fKnownDevicesController selection] valueForKeyPath: @"self"];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"entering...\n");
  
  if ([self setBusy: YES forDeviceWithIdentifier: [selected key]]) {
    NSString *fileName = [NSString stringWithFormat: @"%@/%@.%@.tar.bz2", backupStorePath(), [selected key], [[NSDate date] description]];
    
    vxSync_log3(VXSYNC_LOG_INFO, @"storing phone data in %s\n", NS2CH(fileName));
    
    [self forPhoneWithIdentifier: [selected key] runHelper: [[[self bundle] resourcePath] stringByAppendingFormat: @"/vxBackup"], [selected key], fileName, [[self logLevel] description], nil];
    [self setBusy: NO forDeviceWithIdentifier: [selected key]];
  }

  [releasePool release];
}

- (IBAction) backupDevice:(id)sender {
  [NSThread detachNewThreadSelector: @selector(backupThread:) toTarget: self withObject: nil];
}

- (void) openPanelDidEnd: (NSOpenPanel *)panel returnCode: (int) returnCode contextInfo: (void *) contextInfo {
  NSString *filename = [[panel filenames] count] ? [[panel filenames] objectAtIndex: 0] : nil;
  [NSApp endSheet: panel];
  
  if (filename && returnCode == NSOKButton)
    [NSThread detachNewThreadSelector: @selector(restoreThread:) toTarget: self withObject: filename];
}

- (void) restoreThread: (id) filename {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  id selected = [[fKnownDevicesController selection] valueForKeyPath: @"self"];
  
  if ([self setBusy: YES forDeviceWithIdentifier: [selected key]]) {    
    [self forPhoneWithIdentifier: [selected key] runHelper: [[[self bundle] resourcePath] stringByAppendingFormat: @"/vxRestore"], [selected key], filename, [[self logLevel] description], nil];
    [self setBusy: NO forDeviceWithIdentifier: [selected key]];
  }
  
  [releasePool release];
}

- (IBAction) restoreDevice: (id) sender {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSOpenPanel       *openDialog;
  id selected = [[fKnownDevicesController selection] valueForKeyPath: @"self"];
  
  BOOL isConnected = [[[selected value] objectForKey: @"available"] boolValue];
  
  if (isConnected) {
    openDialog = [NSOpenPanel openPanel];
    [openDialog setCanChooseFiles: YES];
    [openDialog setCanChooseDirectories: NO];
    [openDialog setAllowsMultipleSelection: NO];
    [openDialog beginSheetForDirectory: backupStorePath() file: nil types: [NSArray arrayWithObject:@"bz2"] modalForWindow: window modalDelegate: self didEndSelector: @selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo: nil];
    [openDialog makeKeyWindow];
  }
  
  [releasePool release];
}

- (void) resetThread: (id) selected {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  int ret;
  
  if ([self setBusy: YES forDeviceWithIdentifier: [selected key]]) {    
    ret = [self forPhoneWithIdentifier: [selected key] runHelper: [[[self bundle] resourcePath] stringByAppendingFormat: @"/vxReset"], [selected key], [[self logLevel] description], nil];
    
    if (0 == ret)
      [self setLastSync: nil forDeviceWithIdentifier: [selected key]];
      
    /* client data is no longer valid */
    [self clearClientData: [selected key]];
    
    [self setBusy: NO forDeviceWithIdentifier: [selected key]];
  }  

  [releasePool release];
}

- (void) endResetAlert: (NSAlert *) alert returnCode: (int) returnCode contextInfo: (int *) contextInfo {
  if (0 == returnCode) { /* default button */
    [NSThread detachNewThreadSelector: @selector(resetThread:) toTarget: self withObject: [[fKnownDevicesController selection] valueForKeyPath: @"self"]];
  } /* else ignore */
}

- (IBAction) doResetDevice: (id) sender {
  [[NSAlert alertWithMessageText: @"WARNING" defaultButton: @"Cancel" alternateButton: @"Reset" otherButton: nil informativeTextWithFormat: @"This will remove ALL of the data off the phone and return it to factory settings."] beginSheetModalForWindow: window modalDelegate: self didEndSelector: @selector(endResetAlert:returnCode:contextInfo:) contextInfo: nil];
}

- (IBAction) doShowErrorLog: (id) sender {
  [errorPanel setReleasedWhenClosed: NO];
  [errorPanel makeKeyAndOrderFront: self];
}

- (IBAction) doHideErrorLog: (id) sender {
  [window makeKeyWindow];
  [errorPanel orderOut: self];
}

#pragma mark tableView delegate

- (CGFloat)tableView: (NSTableView *)tableView heightOfRow: (NSInteger)row {
  if (tableView != logTableView)
    return 0.0;

  int rows = [[[[vxSyncLogger defaultLogger] lineCounts] objectAtIndex: row] intValue];  

  return [tableView rowHeight] * ((float) (rows ? rows : 1));
}

- (void) tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  if (tableView != logTableView)
    return;
  
  NSString *currentString = [[[vxSyncLogger defaultLogger] logData] objectAtIndex: row];
  NSColor *txtColor = nil;

  if (NSNotFound != [currentString rangeOfString: @"ERROR"].location)
    txtColor = [NSColor redColor];
  else if (NSNotFound != [currentString rangeOfString: @"WARNING"].location)
    txtColor = [NSColor orangeColor];
  else if (NSNotFound != [currentString rangeOfString: @"vxSyncDevice"].location ||
           NSNotFound != [currentString rangeOfString: @"vxReset"].location ||
           NSNotFound != [currentString rangeOfString: @"vxRestore"].location ||
           NSNotFound != [currentString rangeOfString: @"vxBackup"].location)
    txtColor = [NSColor blueColor];
  else
    txtColor = [NSColor blackColor];

  [cell setTextColor: txtColor];
  [cell setWraps: NO];
}

#pragma mark copy
- (void)copy: (id) sender {
  NSArray *selectedLines = [logDataController selectedObjects];
  NSString *logString = [selectedLines componentsJoinedByString: @""];

  NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
  [pasteBoard declareTypes:[NSArray arrayWithObjects:NSStringPboardType, nil] owner:nil];
  [pasteBoard setString:logString forType:NSStringPboardType];
}

#pragma mark window delegate
- (void)windowWillClose:(NSNotification *)notification {
  [NSApp terminate: self];
}

- (IBAction) logLevelChanged: (id) sender {
  if ([[vxSyncLogger defaultLogger] logLevel] != [[self logLevel] unsignedIntValue])
    [[vxSyncLogger defaultLogger] setLogLevel: [[self logLevel] unsignedIntValue]];
}

- (IBAction) clearErrorLog: (id) sender {
  [[vxSyncLogger defaultLogger] clearLog];
}

- (void) didEndSheet: (NSWindow *) sheet returnCode: (NSInteger) returnCode contextInfo: (void *) contextInfo {
  [sheet orderOut:self];
}

- (IBAction) openPreferenceSheet: (id) sender {
  [NSApp beginSheet: preferencePanel modalForWindow: window modalDelegate: self didEndSelector: @selector(didEndSheet:returnCode:contextInfo:) contextInfo: NULL];
}

- (IBAction) closePreferenceSheet: (id) sender {
  [self preferencesChanged: self];
  [NSApp endSheet: preferencePanel];
}

- (void) readSyncServerPreferences {
  NSDictionary *syncServerDefaults = [[NSUserDefaults standardUserDefaults] persistentDomainForName: @"com.apple.syncserver"];

  /* the domain doesn't exist when the alerts are set to the default (on, 25%) */
  int alertThreshold = syncServerDefaults ? [[syncServerDefaults objectForKey: @"AirbagThreshold"] intValue] : 25;

  const int thresholds[] = {0, 5, 25, 50, -1};
  int i, alertIndex = 0;

  [self setValue: syncServerDefaults ? [syncServerDefaults objectForKey: @"AirbagDisabled"] : [NSNumber numberWithBool: NO] forKeyPath: @"disableSyncAlerts"];

  for (i = 0 ; thresholds[i] != -1 ; i++)
    if (thresholds[i] == alertThreshold) {
      alertIndex = i;
      break;
    }
  
  [self setValue: [NSNumber numberWithInt: alertIndex] forKeyPath: @"syncAlertIndex"];
}

- (IBAction) preferencesChanged: (id) sender {
  NSMutableDictionary *syncServerDefaults = [[[[NSUserDefaults standardUserDefaults] persistentDomainForName: @"com.apple.syncserver"] mutableCopy] autorelease];
  const int thresholds[] = {0, 5, 25, 50, -1};
  int alertIndex = [syncAlertIndex intValue];

  if (thresholds[alertIndex] != 25) {
    if (!syncServerDefaults)
      syncServerDefaults = [NSMutableDictionary dictionary];

    if (![disableSyncAlerts boolValue])
      [syncServerDefaults removeObjectForKey: @"AirbagDisabled"];
    else
      [syncServerDefaults setObject: disableSyncAlerts forKey: @"AirbagDisabled"];
    
    [syncServerDefaults setObject: [NSNumber numberWithInt: thresholds[alertIndex]] forKey: @"AirbagThreshold"];
    
    [[NSUserDefaults standardUserDefaults] setPersistentDomain: syncServerDefaults forName: @"com.apple.syncserver"];
  } else
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName: @"com.apple.syncserver"];

  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
