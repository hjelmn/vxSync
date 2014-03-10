/* (-*- objc -*-)
 * vxSync: vxSyncAppDelegateBluetooth.m
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
