/* (-*- objc -*-)
 *  phone.h
 *  vxSync
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

#import "VXSync.h"
#import "BREWefs.h"

#if !defined(VXPHONE_H)
#define VXPHONE_H

@interface vxPhone : NSObject {
@private
  BREWefs *efs;
  NSString *identifier;
  NSMutableDictionary *formats, *limits, *pictureid;
  NSMutableDictionary *options;
  NSString *imagePath, *branding, *clientDescriptionPath;
  NSBundle *bundle;
}

@property (retain) BREWefs *efs;
@property (retain) NSString *identifier;
@property (retain) NSMutableDictionary *options;
@property (retain) NSBundle *bundle;

@property (retain) NSMutableDictionary *formats;
@property (retain) NSMutableDictionary *limits;
@property (retain) NSString *imagePath;
@property (retain) NSMutableDictionary *pictureid;
@property (retain) NSString *branding;

@property (retain) NSString *clientDescriptionPath;

+ (id) phoneWithIdentifier: (NSString *) identifierIn;
+ (id) phoneWithLocation: (id) location;

+ (void) updatePhoneDictionary: (NSMutableDictionary *) phoneDict;

- (void) cleanup;

- (NSDictionary *) info;

- (id) initWithIdentifier: (NSString *) identifierIn;
- (id) initWithLocation: (id) location;

- (int) limitForEntity: (NSString *) entity;
- (int) formatForEntity: (NSString *) entity;

- (id) getOption: (NSString *) option;

@end

#endif
