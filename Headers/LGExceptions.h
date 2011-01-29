/* (-*- objc -*-)
 * vxSync: LGExceptions.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.4
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(LGEXCEPTIONS_H)
#define LGEXCEPTIONS_H

#include <Cocoa/Cocoa.h>

#include "VXSync.h"
#include "vxPhone.h"

@interface LGExceptions : NSObject {
@private
  vxPhone *phone;

  NSMutableData *internalData;
  int bytesLength, exceptionCount;
  unsigned char *bytes;
}

@property (retain) vxPhone *phone;
@property (retain) NSMutableData *internalData;

+ (id) exceptionsWithPhone: (vxPhone *) phoneIn;
- (id) initWithPhone: (vxPhone *) phoneIn;

- (NSArray *) exceptionsForEvent: (u_int16_t) eventID startTime: (u_int32_t) startTime;
- (void) removeExeptionsForEvent: (u_int16_t) eventID;
- (void) removeAllExceptions;

- (void) addExceptionsFromArray: (NSArray *) exceptions eventID: (u_int16_t) eventID;
- (int) commitChanges;
@end

#endif
