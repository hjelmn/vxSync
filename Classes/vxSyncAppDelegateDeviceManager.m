/* (-*- objc -*-)
 * vxSync: vxSyncAppDelegateDeviceManager.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#import "vxSyncAppDelegate.h"
#import "vxPhone.h"

static inline void update_connections (NSMutableDictionary *device) {
  NSString *connections = nil;

  if ([[device objectForKey: @"locations"] count]) {
    for (id location in [device objectForKey: @"locations"]) {
      @try {
        NSString *bus = [[location componentsSeparatedByString: @"::"] objectAtIndex: 0];
        connections = !connections ? bus : [connections stringByAppendingFormat: @", %@", bus];
      } @catch (NSException *e) {
        /* ignore */
      }
    }
  } else {
    connections = @"Not connected";
  }
    
  [device setObject: connections forKey: @"connections"];
}

static inline void location_left (NSDictionaryController *controller, NSString *location, BOOL removeOnDisconnect) {
  for (id item in [controller arrangedObjects]) {
    NSDictionary *device = [item value];
    NSMutableSet *locations   = [NSMutableSet setWithArray: [device objectForKey: @"locations"]];
    
    if ([locations count] && [locations containsObject: location]) {
      NSMutableDictionary *updatedDevice = [[device mutableCopy] autorelease];

      [locations removeObject: location];
      [updatedDevice setObject: [locations allObjects] forKey: @"locations"];
      update_connections (updatedDevice);
      
      if (!removeOnDisconnect) {
        if ([locations count] == 0)
          set_disconnected (updatedDevice);
        
        [item setValue: updatedDevice];
      } else {
        if ([locations count] == 0)
          [controller removeObject: item];
        else
          [item setValue: updatedDevice];
      }
      
      return;
    }
  }
}

@implementation vxSyncAppDelegate (deviceManager)

- (IBAction) doAddDevice: (id) sender {
  /* force a bluetooth scan */
  lastScan = [NSDate distantPast];

  /* start the add sheet */
  [NSApp beginSheet: addPanel modalForWindow: window modalDelegate: self didEndSelector: nil contextInfo: nil];
}

- (IBAction) doCancelAddDevice:(id)sender {
  [addPanel orderOut: nil];
  [NSApp endSheet: addPanel];
}

- (IBAction) doAddSelectedDevice: (id) sender {
  id item = [[fUnknownDevicesController selection] valueForKeyPath: @"self"];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"selection = %s\n", NS2CH(item));
  
  if ([item value] && [self setBusy:YES animation: NO] != -1) {
    NSString *identifier = [item key];
    NSMutableDictionary *modEntry = [[item value] mutableCopy];

    /* first remove the device from the unknown devices controller */
    [fUnknownDevicesController remove: self];

    [modEntry setObject: [NSMutableDictionary dictionary] forKey: @"calendar"];
    [modEntry setValue: [NSNumber numberWithBool: YES] forKeyPath: @"calendar.sync"];
    [modEntry setValue: [NSNumber numberWithBool: YES] forKeyPath: @"calendar.syncAll"];
    [modEntry setValue: [NSMutableArray array] forKeyPath: @"calendar.list"];
    [modEntry setValue: [NSNumber numberWithFloat: 0.95] forKeyPath: @"calendar.eventThreshold"];
    
    [modEntry setObject: [NSMutableDictionary dictionary] forKey: @"contacts"];
    [modEntry setValue: [NSNumber numberWithBool: YES] forKeyPath: @"contacts.sync"];
    [modEntry setValue: [NSNumber numberWithBool: YES] forKeyPath: @"contacts.syncAll"];
    [modEntry setValue: [NSMutableArray array] forKeyPath: @"contacts.list"];
    [modEntry setValue: [NSNumber numberWithBool: NO] forKeyPath: @"contacts.syncOnlyWithPhoneNumbers"];
    
    [modEntry setObject: [NSMutableDictionary dictionary] forKey: @"notes"];
    [modEntry setValue: [NSNumber numberWithBool: YES] forKeyPath: @"notes.sync"];
    
    add_value_to_controller (fKnownDevicesController, modEntry, identifier);

    [self setBusy: NO animation:NO];
  }
  
  [addPanel orderOut: nil];
  [NSApp endSheet: addPanel];
}

- (void) clearClientData: (NSString *) uniqueID {
  NSMutableDictionary *rootObject = [[[[NSUserDefaults standardUserDefaults] persistentDomainForName: @"com.enansoft.vxSync.LGPBEntryFile"] mutableCopy] autorelease];
  [rootObject removeObjectForKey: uniqueID];
  [[NSUserDefaults standardUserDefaults] setPersistentDomain: rootObject forName: @"com.enansoft.vxSync.LGPBEntryFile"];
  [[NSUserDefaults standardUserDefaults] removePersistentDomainForName: [NSString stringWithFormat: @"com.enansoft.vxSync.%@", uniqueID]];
  
  if ([[ISyncManager sharedManager] clientWithIdentifier: [NSString stringWithFormat: @"com.enansoft.vxSync.%@", uniqueID]])
    [[ISyncManager sharedManager] unregisterClient: [[ISyncManager sharedManager] clientWithIdentifier: [NSString stringWithFormat: @"com.enansoft.vxSync.%@", uniqueID]]];
}

- (IBAction) doRemoveDevice: (id) sender {
  id selected = [[fKnownDevicesController selection] valueForKeyPath: @"self"];
  
  if ([selected value] && [self setBusy: YES forDeviceWithIdentifier: [selected key]]) {
    NSMutableDictionary *device = [[[selected value] mutableCopy] autorelease];
    NSString     *identifier    = [selected key];
    
    [self clearClientData: identifier];
    [fKnownDevicesController remove: self];
    
    if ([[device objectForKey: @"available"] boolValue]) {
      /* clear device preferences */
      [device removeObjectForKey: @"calendar"];
      [device removeObjectForKey: @"notes"];
      [device removeObjectForKey: @"contacts"];
      [device removeObjectForKey: @"LastSync"];
      [device removeObjectForKey: @"status"];
      [device removeObjectForKey: @"busy"];
      
      /* add the device to the unknown devices list */
      add_value_to_controller(fUnknownDevicesController, device, identifier);
    }

    /* no need to set ready */
  }
}


- (void) scanDeviceQuick: (id) location {
  NSArray *locationComponents = [location componentsSeparatedByString: @"::"];
  NSString *bus               = [locationComponents objectAtIndex: 0];
  NSString *busLocation       = [locationComponents objectAtIndex: 1];
  NSMutableDictionary *oldData = nil; /* or new if there isn't any old data */
  NSString *identifier;
  BOOL ready = YES;
  vxPhone *_phone = nil;
  id knownItem, unknownItem;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"checking device at location: %s\n", NS2CH(location));
  if ([bus isEqualToString: @"USB"])
    identifier = [BREWefs identifierForDevice: [IOUSBPhone phoneWithLocation: busLocation]];
  else if ([bus isEqualToString: @"Bluetooth"])
    identifier = [BREWefs identifierForDevice: [IOBluetoothPhone phoneWithLocation: busLocation]];  
  
  if (!identifier) {
    return;
  }
  
  knownItem = find_object_with_key(fKnownDevicesController, identifier);
  unknownItem = find_object_with_key(fUnknownDevicesController, identifier);
  
  if (knownItem) {
    /* known device -- update when selected */
    oldData = [[[knownItem value] mutableCopy] autorelease];
  } else if (unknownItem) {
    /* unknown device seen previously -- don't scan, just append the location */
    oldData = [[[unknownItem value] mutableCopy] autorelease];
  } else {
    /* unknown device -- perform full scan */
    oldData = [NSMutableDictionary dictionaryWithObject: [NSMutableArray array] forKey: @"locations"];
  }
  
  [[oldData objectForKey: @"locations"] addObject: location];
  [oldData setObject: [NSNumber numberWithBool: YES] forKey: @"available"];
  update_connections(oldData);
  
  if (knownItem) {
    [knownItem setValue: oldData];
    ready = [self setBusy: YES forDeviceWithIdentifier: identifier];
    if (ready)
      [self setStatus: @"Scanning..." forDeviceWithIdentifier: identifier];
  }

  if (!ready)
    /* done scanning */
    return;
  
  _phone = [vxPhone phoneWithLocation: location];
  vxSync_log3(VXSYNC_LOG_INFO, @"new data = %s\n", NS2CH([_phone info]));
  if (_phone)
    [oldData addEntriesFromDictionary: [_phone info]];
  [_phone cleanup];
  
  [oldData setValue: [NSNumber numberWithBool: NO] forKeyPath: @"busy"];
  [oldData setValue: nil forKeyPath: @"status"];

  if (knownItem) {
    [knownItem setValue: oldData];
  } else if (!unknownItem) {
    add_value_to_controller(fUnknownDevicesController, oldData, identifier);
  } else {
    [unknownItem setValue: oldData];
  }
}

- (void) addLocation: (NSString *) location {
  vxSync_log3(VXSYNC_LOG_INFO, @"LG Phone connected: location = %s\n", NS2CH(location));
  [self scanDeviceQuick: location];
}

- (void) remLocation: (NSString *) location {
  vxSync_log3(VXSYNC_LOG_INFO, @"LG Phone disconnected: location = %s\n", NS2CH(location));
  location_left(fKnownDevicesController, location, NO);
  location_left(fUnknownDevicesController, location, YES);
}

- (void) deviceArrived: (id) location {
  [self addLocation: [location object]];
}

- (void) deviceLeft: (id) location {
  [self remLocation: [location object]];
}

@end
