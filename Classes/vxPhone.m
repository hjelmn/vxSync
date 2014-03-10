/* (-*- objc -*-)
 * vxSync: vxPhone.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.6
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

#include "VXSync.h"

#include "vxPhone.h"

#include "IOUSBPhone.h"
#include "IOBluetoothPhone.h"

@interface vxPhone (hidden)
- (int) readPhonePreferences;
+ (id) phoneWithModel: (NSString *) model;
- (id) initWithModel: (NSString *) model;
@end

@interface vxPhone (plugin)
- (int) matchPlugin;
- (int) matchPluginWithModel: (NSString *) model;
@end

@implementation vxPhone

@synthesize efs, identifier, formats, limits, options, pictureid, imagePath, branding, bundle, clientDescriptionPath;

- (void) cleanup {
  [efs doneWithDevice];

  vxSync_log3(VXSYNC_LOG_INFO, @"deallocating vxPhone object\n");
  
  [self setIdentifier: nil];
  [self setFormats: nil];
  [self setLimits: nil];
  [self setOptions: nil];
  [self setPictureid: nil];
  [self setImagePath: nil];
  [self setEfs: nil];
  [self setBundle: nil];
  [self setClientDescriptionPath: nil];
}

- (void) dealloc {
  [self cleanup];
  
  [super dealloc];
}

+ (id) phoneWithIdentifier: (NSString *) identifierIn {
  return [[[vxPhone alloc] initWithIdentifier: identifierIn] autorelease];
}

+ (id) phoneWithLocation: (NSString *) locationIn {
  return [[[vxPhone alloc] initWithLocation: locationIn] autorelease];
}

+ (id) phoneWithModel: (NSString *) model {
  return [[[vxPhone alloc] initWithModel: model] autorelease];
}

+ (void) updatePhoneDictionary: (NSMutableDictionary *) phoneDict {
  vxPhone *dummyPhone = [vxPhone phoneWithModel: [phoneDict objectForKey: @"model"]];

  if (dummyPhone)
    [phoneDict addEntriesFromDictionary: [dummyPhone info]];
}

- (id) initWithModel: (NSString *) model {
  self = [self init];
  if (!self)
    return nil;

  int ret = [self matchPluginWithModel: model];
  if (ret)
    return nil;

  return self;
}

- (id) initWithLocation: (NSString *) locationIn {
  self = [self init];
  if (!self)
    return nil;

  NSArray *locationComponents = [locationIn componentsSeparatedByString: @"::"];
  NSString *bus         = [locationComponents objectAtIndex: 0];
  NSString *busLocation = [locationComponents objectAtIndex: 1];
  id <PhoneDevice> _device = nil;

  if ([bus isEqualToString: @"USB"])
    _device = [IOUSBPhone phoneWithLocation: busLocation];
  else if ([bus isEqualToString: @"Bluetooth"])
    _device = [IOBluetoothPhone phoneWithLocation: busLocation];

  if (!_device) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not open device @ %s\n", NS2CH(locationIn));
    
    return nil;
  }

  BREWefs *_efs = [BREWefs efsWithDevice: _device];

  if (!_efs)
    return nil;

  [self setEfs: _efs];
  [self setIdentifier: [_efs valueForKey: @"identifier"]];

  (void) [self readPhonePreferences];
  if (![self valueForKey: @"options"])
    vxSync_log3(VXSYNC_LOG_WARNING, @"Could not read phone preferences. Continuing anyway....\n");

  [self setBundle: vxSyncBundle ()];

  if ([self matchPlugin] != 0)
    return nil;
  
  return self;
}

- (NSDictionary *) info {
  NSDictionary *phoneInfo = [efs phoneInfo];
  NSMutableDictionary *info = [NSMutableDictionary dictionary];

  if (phoneInfo)
    [info addEntriesFromDictionary: phoneInfo];

  [info addEntriesFromDictionary: [self dictionaryWithValuesForKeys: [NSArray arrayWithObjects: @"branding", @"imagePath", nil]]];

  return info;
}

- (NSObject *) getPreference: (NSString *) key {
  return [[[NSUserDefaults standardUserDefaults] persistentDomainForName: kBundleDomain] objectForKey: key];
}

- (int) readPhonePreferences {
  /* [NSBundle bundleForClass: [self class]] */
  NSDictionary *phones;

  phones = (NSDictionary *) [self getPreference: @"Phones"];
  [self setOptions: [[[phones objectForKey: identifier] mutableCopy] autorelease]];

  vxSync_log3(VXSYNC_LOG_INFO, @"options = %s\n", NS2CH(options));
  
  return 0;
}

- (id) getOption: (NSString *) option {
  return [options valueForKeyPath: option];
}

- (id) init {
  self = [super init];
  
  [self setBundle: vxSyncBundle ()];
  
  return self;
}

- (id) initWithIdentifier: (NSString *) identifierIn {
  /* try use then try bluetooth (need to check the bluetooth flag) */
  Class sources[] = {[IOUSBPhone class], [IOBluetoothPhone class], nil};
  int i;
  
  self = [self init];
  if (!self)
    return nil;
  
  if (![(NSNumber *)[self getPreference: @"UseBluetooth"] boolValue])
    sources[1] = nil;

  [self setIdentifier: [[identifierIn copy] autorelease]];
  
  vxSync_log3(VXSYNC_LOG_INFO, @"locating device with identifier: %s\n", NS2CH(identifierIn));
  
  for (i = 0 ; sources[i] ; i++) {
    vxSync_log3(VXSYNC_LOG_INFO, @"scanning using source: %s\n", NS2CH(sources[i]));
    NSSet *locations = [sources[i] scanDevices];
    
    for (id _location in locations) {
      NSArray *locationComponents = [_location componentsSeparatedByString: @"::"];
      NSString *busLocation = [locationComponents objectAtIndex: 1];
      id <PhoneDevice> _device = [sources[i] phoneWithLocation: busLocation];
      BREWefs *_efs = [BREWefs efsWithDevice: _device];
      NSString *_identifier = [_efs identifier];
      
      vxSync_log3(VXSYNC_LOG_INFO, @"checking again device at location %s (%s)\n", NS2CH(_location), NS2CH(_identifier));
      
      if ([_identifier isEqualToString: identifierIn]) {
        vxSync_log3(VXSYNC_LOG_INFO, @"device found\n");
        
        [self setEfs: _efs];
        
        (void) [self readPhonePreferences];
        if (![self options])
          vxSync_log3(VXSYNC_LOG_WARNING, @"could not read phone preferences. continuing anyway....\n");
        
        if ([self matchPlugin]) {
          vxSync_log3(VXSYNC_LOG_ERROR, @"no plugin matches model\n");
          
          return nil;
        }
        
        return self;
      } else {
        [_efs doneWithDevice];
      }
    }
  }
  
  vxSync_log3(VXSYNC_LOG_INFO, @"could not locate device\n");

  return nil;
}

- (int) limitForEntity: (NSString *) entity {
  return [[limits objectForKey: entity] integerValue];
}

- (int) formatForEntity: (NSString *) entity {
  return [[formats objectForKey: entity] integerValue];
}

@end

#if defined(VXPHONE_UNIT_TEST)
#warn "vxPhone unit test"

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];

  vxSync_log_set_level(2);
  vxPhone *vx5500 = [vxPhone phoneWithIdentifier: @"07028d16"];
  
  printf ("limits = %s\n", [[[vx5500 limits] description] UTF8String]);
  printf ("formats = %s\n", [[[vx5500 formats] description] UTF8String]);
  printf ("info = %s\n", [[[vx5500 info] description] UTF8String]);
  
  [releasePool release];

  return 0;
}
#endif
