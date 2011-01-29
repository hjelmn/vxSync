/* (-*- objc -*-)
 * vxSync: LGCalendar.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.4
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
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
