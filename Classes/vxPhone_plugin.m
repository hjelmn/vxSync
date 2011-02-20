/* (-*- objc -*-)
 * vxSync: vxPhone_plugin.h
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.4
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "vxPhone.h"

@interface vxPhone (plugin)
- (int) matchPlugin;
- (int) matchPluginWithModel: (NSString *) model;
@end

@interface vxPhone (hidden)
+ (id) phoneWithModel: (NSString *) model;
- (id) initWithModel: (NSString *) model;
@end

@implementation vxPhone (plugin)
- (int) matchPlugin {
  return [self matchPluginWithModel: [efs model]];
}

- (int) matchPluginWithModel: (NSString *) model {
#if !defined(VXPHONE_DISABLE_PLUGINS)
  NSString *pluginPath = [[self bundle] builtInPlugInsPath];
  NSError *error = nil;
  NSArray *plugins = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath: pluginPath error: &error] filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"SELF endswith[c] %@", @".vxphone"]];

  NSString *modelNumber = [model substringFromIndex: 2];
  NSString *carrierID   = [model substringToIndex: 2]; /* VX/VN - Verizon, AX - Alltel, LX - Sprint, CX - Telus or Bell (Canadian) */
  NSString *matchModel  = [NSString stringWithFormat: @"VX%@", modelNumber];

  vxSync_log3(VXSYNC_LOG_INFO, @"checking for plugin matching: model #: %s, carrierID: %s\n", NS2CH(modelNumber), NS2CH(carrierID));

  if ([carrierID isEqualToString: @"LX"]) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"Sprint phones are not supported at this time. Contact the author for support.\n");
    return -1;
  }

  if (error) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not get a listing of plugins: reason = %s. bundle path = %s, plugin path = %s, resource path = %s\n", NS2CH(error), NS2CH([bundle bundlePath]), NS2CH(pluginPath), NS2CH([bundle resourcePath]));
    return -1;
  }

  for (id _plugin in plugins) {
    NSBundle *pluginBundle = [NSBundle bundleWithPath: [pluginPath stringByAppendingPathComponent: _plugin]];
    NSDictionary *_pluginData = [NSDictionary dictionaryWithContentsOfFile: [pluginBundle pathForResource: @"vxPhone" ofType: @"plist"]];

    if ([[_pluginData objectForKey: @"model"] isEqualToString: matchModel]) {
      vxSync_log3(VXSYNC_LOG_INFO, @"using plugin %s\n", NS2CH(_plugin));

      [self setLimits: [_pluginData objectForKey: @"entity limits"]];
      [self setFormats: [_pluginData objectForKey: @"formats"]];
      [self setPictureid: [_pluginData objectForKey: @"pictureid"]];
      [self setBranding: [_pluginData objectForKey: @"branding"]];
      [self setImagePath: [pluginBundle pathForResource: @"vxPhone" ofType: @"png"]];
      [self setClientDescriptionPath: [pluginBundle pathForResource: @"vxClient" ofType: @"plist"]];

      return 0;
    }
  }
#else
  return 0;
#endif

  return -1;
}

@end
