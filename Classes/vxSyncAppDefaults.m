/* (-*- objc -*-)
 * vxSync: vxSyncAppDefaults.m
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

@implementation vxSyncAppDelegate (defaults)

- (void) defaultsInitialize {
  NSDictionary *initialDefaults = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInteger: 1], @"LogLevel",
                                   [NSDictionary dictionary], @"Phones",
                                   nil];
  [[NSUserDefaults standardUserDefaults] registerDefaults: initialDefaults];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
