/* (-*- objc -*-)
 * vxSync: vxSyncAppDelegateBluetooth.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#import "vxSyncAppDelegate.h"

#define kBluetoothSleep     1000000 /* useconds */
#define kBluetoothScanSleep 60      /* seconds  */

@implementation vxSyncAppDelegate (bluetooth)

- (void) initBluetooth {
  useBluetooth = [[[defaultsController values] valueForKeyPath: @"UseBluetooth"] boolValue];
  
  runBluetoothThread = YES;
  /* used to limit how often we scan for bluetooth devices */
  lastScan = [NSDate distantPast];
  [NSThread detachNewThreadSelector: @selector(scanBluetooth:) toTarget: self withObject: nil];
}

- (void) finalizeBluetooth {
  runBluetoothThread = NO;
}

- (bool) useBluetooth {
  return useBluetooth;
}

- (IBAction) toggleBluetooth: (id) sender {
  bool _value = [[[defaultsController values] valueForKeyPath: @"UseBluetooth"] boolValue];

  if (!useBluetooth && _value)
    lastScan = [NSDate distantPast];

  useBluetooth = _value;
}

#pragma mark working thread
- (void) scanBluetooth: (id) sender {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSMutableSet *lastSet = [NSMutableSet set];

  while (runBluetoothThread) {
    unsigned int intervalSinceLastBTScan = [[NSDate date] timeIntervalSinceDate: lastScan];
    
    if (useBluetooth && intervalSinceLastBTScan > kBluetoothScanSleep) {
      [btScanStatus setStringValue: @"Scanning for connected devices"];
      [btScanStatus setHidden: NO];
      [btScanIndicator startAnimation: self];
      [updateIndicator startAnimation: self];
      
      NSSet *foundLocations = [IOBluetoothPhone scanDevices];
      NSMutableSet *addLocations = [[foundLocations mutableCopy] autorelease];
      NSMutableSet *remLocations = [[lastSet mutableCopy] autorelease];
      
      [addLocations minusSet: lastSet];
      [remLocations minusSet: foundLocations];
      
      for (id location in addLocations)
        [self addLocation: location];
      for (id location in remLocations)
        [self remLocation: location];
      
      [lastSet removeAllObjects];
      [lastSet addObjectsFromArray: [foundLocations allObjects]];
      
      lastScan = [NSDate date];
      
      [btScanStatus setHidden: YES];
      [btScanIndicator stopAnimation: self];
      [updateIndicator stopAnimation: self];
    }
    if (!useBluetooth && [lastSet count]) {
      for (id location in lastSet) {
        [self remLocation: location];
      }

      [lastSet removeAllObjects];
    }

    usleep (kBluetoothSleep);
  }
  
  [releasePool release];
}


@end
