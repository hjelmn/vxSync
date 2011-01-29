/* (-*- objc -*-)
 *  phone.h
 *  vxSync
 *
 *  Created by Nathan Hjelm on 5/17/10.
 *  Copyright 2010 __MyCompanyName__. All rights reserved.
 *
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
