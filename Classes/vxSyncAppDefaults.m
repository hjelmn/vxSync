/* (-*- objc -*-)
 * vxSync: vxSyncAppDefaults.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#import "vxSyncAppDelegate.h"

@implementation vxSyncAppDelegate (defaults)

- (void) defaultsInitialize {
  NSDictionary *initialDefaults = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInteger: 1], @"LogLevel",
                                   [NSDictionary dictionary], @"Phones",
                                   nil];
  [[NSUserDefaults standardUserDefaults] registerDefaults: initialDefaults];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
