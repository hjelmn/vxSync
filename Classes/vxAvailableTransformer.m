/* (-*- objc -*-)
 * vxSync: vxAvailableTransformer.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * 0.8.2
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
