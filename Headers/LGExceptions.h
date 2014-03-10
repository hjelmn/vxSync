/* (-*- objc -*-)
 * vxSync: LGExceptions.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.4
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
