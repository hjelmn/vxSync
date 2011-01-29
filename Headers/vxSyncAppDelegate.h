/* (-*- objc -*-)
 *  vxSyncAppDelegate.h
 *  vxSync
 *
 *  Created by Nathan Hjelm on 12/5/10.
 *  Copyright 2010 __MyCompanyName__. All rights reserved.
 */

#import "VXSync.h"
#import "IOUSBPhone.h"
#import "IOBluetoothPhone.h"

#import <Cocoa/Cocoa.h>

extern mach_port_t masterPort;

NSDictionary *defaultFolderAttributes (void);
NSString *applicationSupportPath (void);
NSString *backupStorePath (void);
id find_object_with_key (NSDictionaryController *controller, NSString *key);
void convert_old_to_new_path (NSMutableDictionary *dict, NSString *oldKey, NSString *newKeyPath);
void add_value_to_controller (NSDictionaryController *controller, NSObject *value, NSString *key);
void set_disconnected (NSMutableDictionary *device);

@interface vxSyncAppDelegate : NSObject {
  NSWindow *window;
  IBOutlet NSUserDefaultsController *defaultsController;
  IBOutlet NSView *phoneViewer;
  IBOutlet NSDictionaryController *fKnownDevicesController, *fUnknownDevicesController;
  IBOutlet NSProgressIndicator *progIndicator, *updateIndicator, *btScanIndicator;
  IBOutlet NSArrayController *calendarController, *groupController;
  IBOutlet NSTextField *btScanStatus, *actionStatus;
  IBOutlet NSCollectionView *addView;
  IBOutlet NSPanel *errorPanel;
  IBOutlet NSTextView *errorText;
  
  IBOutlet NSPanel        *addPanel;
  
  IBOutlet NSArrayController *logDataController;
  IBOutlet NSTableView *logTableView;
  IBOutlet NSTableColumn *logTableColumn;
@private
  NSDictionary *fUnknownDevices;
  bool isBusy;
  bool useBluetooth;
  NSDate *lastScan;
  bool runBluetoothThread;
  NSMutableDictionary *statuses;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSUserDefaultsController *defaultsController;
@property (assign) IBOutlet NSDictionaryController *fKnownDevicesController;
@property (assign) IBOutlet NSDictionaryController *fUnknownDevicesController;
@property (retain) NSDictionary *fUnknownDevices;
@property (readwrite) bool isBusy;
@property (assign) IBOutlet NSProgressIndicator *progIndicator;
@property (assign) IBOutlet NSArrayController *calendarController;
@property (assign) IBOutlet NSArrayController *groupController;
@property (assign) IBOutlet NSProgressIndicator *updateIndicator;
@property (assign) IBOutlet NSProgressIndicator *btScanIndicator;
@property (assign) IBOutlet NSTextField *btScanStatus;
@property (assign) IBOutlet NSCollectionView *addView;
@property (assign) IBOutlet NSTextField *actionStatus;
@property (assign) IBOutlet NSPanel *errorPanel;
@property (assign) IBOutlet NSTextView *errorText;
@property (assign) IBOutlet NSArrayController *logDataController;
@property (assign) IBOutlet NSTableView *logTableView;
@property (assign) IBOutlet NSTableColumn *logTableColumn;

- (void) applicationWillFinishLaunching:(NSNotification *)aNotification;
- (void) applicationDidFinishLaunching:(NSNotification *)aNotification;

- (NSString*) versionString;
- (IBAction) doDonate: (id) sender;

- (int) setBusy: (bool) value animation: (bool) startStopAnimation;

- (BOOL) setBusy: (BOOL) _busy forDeviceWithIdentifier: (NSString *) _identifier;
- (void) setStatus: (NSString *) _status forDeviceWithIdentifier: (NSString *) _identifier;

- (void) updateGroups: (id) sender;
- (void) updateCalendars: (id) sender;

- (IBAction) sync: (id) sender;
- (IBAction) doResetDevice: (id) sender;
- (IBAction) backupDevice: (id)sender;
- (IBAction) restoreDevice: (id) sender;

- (IBAction) doShowErrorLog: (id) sender;
- (IBAction) doHideErrorLog: (id) sender;

- (IBAction) logLevelChanged: (id) sender;

@end

@interface vxSyncAppDelegate (defaults)
- (void) defaultsInitialize;
@end

@interface vxSyncAppDelegate (deviceManager)
- (IBAction) doAddDevice: (id) sender;
- (IBAction) doAddSelectedDevice: (id) sender;
- (IBAction) doRemoveDevice: (id) sender;
- (IBAction) doCancelAddDevice:(id)sender;
- (void) deviceArrived: (id) location;
- (void) deviceLeft: (id) location;
- (void) addLocation: (NSString *) location;
- (void) remLocation: (NSString *) location;
- (void) clearClientData: (NSString *) uniqueID;
@end

@interface vxSyncAppDelegate (bluetooth)
- (void) initBluetooth;
- (void) finalizeBluetooth;
- (bool) useBluetooth;
- (IBAction) toggleBluetooth: (id) sender;
@end