/* (-*- objc -*-)
 * vxSync: LGCalendar.h
 * Copyright (C) 2009-2011 Nathan Hjelm
 * v0.8.5
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

#if !defined(LGCALENDAR_H)
#define LGCALENDAR_H

#include "VXSync.h"

#include "LGExceptions.h"

@interface LGCalendar : NSObject <LGData> {
@private
  vxPhone *phone;

  int eventLimit, taskLimit;

  id <LGDataDelegate> delegate;

  unsigned char *usedEntries;
  NSMutableArray *intCalendars;
  NSMutableData *internalData, *usedEntriesData;
  unsigned char *bytes;
  int eventCount;
  LGExceptions *exceptionsData;
  NSDictionary *newEventCalendar;
  ISyncSessionDriver *sessionDriver;
  NSString *newEventCalendarTitle;
  int noRingIndex;
}

@property (retain) vxPhone *phone;

@property (retain) id <LGDataDelegate> delegate;
@property (retain) NSMutableData *usedEntriesData;
@property (retain) NSMutableArray *intCalendars;
@property (retain) NSMutableData *internalData;
@property (retain) LGExceptions *exceptionsData;

@property (retain) NSDictionary *newEventCalendar;
@property (retain) NSString *newEventCalendarTitle;
@end

#endif
