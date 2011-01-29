/* (-*- objc -*-)
 * vxSync: vxAvailableTransformer.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * 0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "vxAvailableTransformer.h"

@implementation vxAvailableTransformer

+ (Class)transformedValueClass {
  return [NSString self];
}

+ (BOOL)allowsReverseTransformation {
  return NO;
}

- (id)transformedValue:(id)beforeObject {
  NSString *filename = [beforeObject boolValue] ? @"available" : @"unavailable";
  return [vxSyncBundle() pathForResource: filename ofType: @"tif"];
}

@end

@implementation vxAvailableTransformerText

+ (Class)transformedValueClass {
  return [NSString self];
}

+ (BOOL)allowsReverseTransformation {
  return NO;
}

- (id)transformedValue:(id)beforeObject {
  return [beforeObject boolValue] ? @"Connected" : @"Not connected";
}

@end

@implementation noSelectionTransformer

+ (Class)transformedValueClass {
  return [NSString self];
}

+ (BOOL)allowsReverseTransformation {
  return NO;
}

- (id)transformedValue:(id)beforeObject {
  return [NSNumber numberWithBool: NSNoSelectionMarker == beforeObject];
}

@end