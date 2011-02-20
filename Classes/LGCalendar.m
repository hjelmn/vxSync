/* (-*- objc -*-)
 * vxSync: LGCalendar.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.4
 *
 * Changes:
 *  - 0.3.1 - Move LGException class into a seperate file. Bug fixes and code cleanup
 *  - 0.3.0 - Cleaner code. Support for commitChanges. Better support for all day events. Multiple calendars support.
 *  - 0.2.3 - Bug fixes
 *  - 0.2.0 - Initial release
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include <stdlib.h>
#include <stdio.h>

#include "LGCalendar.h"

#define kRecurrenceExceptionBit      (1<<4)
#define kEventBlockReadSize          6

typedef struct lg_schedule_event lg_sched_event_t;

@interface LGCalendar (hidden)
- (NSMutableDictionary *) newCalendarForPhone;

- (void) addEventsToCalendars: (NSMutableDictionary *) dict;

- (void) eventAlarm: (lg_sched_event_t *) event owner: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) dict;
- (void) eventRecurrence: (lg_sched_event_t *) event owner: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) dict;

- (int) setEvent: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut atIndex: (u_int32_t) eventIndex isNew: (BOOL) isNew identifier: (NSString *) identifier;
- (int) setAlarmForEvent: (NSDictionary *) event to: (NSDictionary *) alarmDict formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier;
- (int) setRecurrenceForEvent: (NSDictionary *) event to: (NSDictionary *) recurrenceRecord formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier;
- (int) recurrence: (u_int32_t) recurrence until: (u_int32_t) recurrence_end toDict: (NSMutableDictionary *) recurrenceRecord;

- (int) refreshInternalCalendars;
- (int) commitCalendars;
- (void) findNoRingIndex;
@end

static NSString *days[] = {@"sunday", @"monday", @"tuesday", @"wednesday", @"thursday", @"friday", @"saturday"};

@implementation LGCalendar

@synthesize phone, delegate, usedEntriesData, intCalendars, internalData, exceptionsData, newEventCalendar, newEventCalendarTitle;

+ (id) sourceWithPhone: (vxPhone *) phoneIn {
  return [[[LGCalendar alloc] initWithPhone: phoneIn] autorelease];
}

- (NSString *) dataSourceIdentifier {
  return @"com.enansoft.calendar";
}

- (NSArray *) supportedEntities {
  return [NSArray arrayWithObjects: EntityCalendar, EntityEvent, EntityAudioAlarm, EntityDisplayAlarm, EntityRecurrence, nil];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];
  if (!self)
    return nil;
  
  [self setPhone: phoneIn];

  [self setNewEventCalendarTitle: [phone valueForKeyPath: @"options.calendar.storeIn"]];

  eventLimit = [phone limitForEntity: EntityEvent];
  taskLimit  = 0;

  [self setUsedEntriesData: [NSMutableData dataWithLength: eventLimit]];
  usedEntries = [usedEntriesData mutableBytes];

  return self;
}

- (void) dealloc {
  [self setPhone: nil];
  [self setDelegate: nil];
  [self setUsedEntriesData: nil];
  [self setIntCalendars: nil];
  [self setInternalData: nil];
  [self setExceptionsData: nil];
  [self setNewEventCalendar: nil];
  [self setNewEventCalendarTitle: nil];

  [super dealloc];
}

- (void) findNoRingIndex {
  unsigned char buffer[1204];
  int i;
  
  for (i = 0 ; i < 0x63 ; i++) {
    memset (buffer, 0, 1024);
    buffer[0] = 0xf1;
    buffer[1] = 0x2d;
    OSWriteLittleInt16 (buffer, 2, i);
    
    (void)[[phone efs] send_recv_message: buffer sendLength: 10 sendBufferSize: 1024 recvTo: buffer recvLength: 1024];
    
    vxSync_log3(VXSYNC_LOG_DEBUG, @"found ringtone %s at index: %x\n", buffer + 14, i);
    if (strcmp ((char *)(buffer + 14), "No Ring") == 0) {
      noRingIndex = i - 1;
      break;
    }
  }
}

- (int) refreshInternalData {
  int readCount, i, j, fd;

  printf ("Reading calendar...\n");
  vxSync_log3(VXSYNC_LOG_INFO, @"refreshing internal data. previous internal data = %p\n", internalData);

  /* allocate buffers */
  [self setInternalData: [NSMutableData dataWithLength: eventLimit * sizeof (lg_sched_event_t) + 4]];

  bytes = [internalData mutableBytes];
  
  fd = [[phone efs] open: VXSchedulePath withFlags: O_RDWR];
  if (-1 == fd)
    return -1;
  
  [[phone efs] read: fd to: bytes count: 2];
  
  eventCount = OSReadLittleInt16 (bytes, 0);

  /* read blocks of the file until we find all the events */
  for (i = 0, readCount = 0 ; i < eventLimit && readCount < eventCount ; i += kEventBlockReadSize) {
    u_int32_t offset = 2 + i * sizeof (lg_sched_event_t);
    [[phone efs] read: fd to: bytes + offset count: kEventBlockReadSize * sizeof (lg_sched_event_t)];
    
    for (j = 0 ; j < kEventBlockReadSize && readCount < eventCount ; j++) {
      if (OSReadLittleInt32 (bytes + offset, 0) == offset) {
        usedEntries[i + j] = 1;
        readCount++;
      }

      offset += sizeof (lg_sched_event_t);
    }
  }
  [[phone efs] close: fd];

  if (i == 0) i = 1;

  vxSync_log3(VXSYNC_LOG_INFO, @"finished updating internal data: %i bytes for %d events\n", (i-1) * kEventBlockReadSize *sizeof (lg_sched_event_t), eventCount);
  vxSync_log3(VXSYNC_LOG_INFO, @"used entries = %s\n", [[usedEntriesData description] UTF8String]);
  
  [self setExceptionsData: [LGExceptions exceptionsWithPhone: phone]];

  [self findNoRingIndex];
  
  return [self refreshInternalCalendars];
}

/* 
   memberKey can either be events or tasks
*/
- (NSString *) getCalendarIdentifierForEvent: (NSDictionary *) event memberKey: (NSString *) memberKey {
  for (id calendar in intCalendars) {
    NSArray *foundMembers = [[calendar objectForKey: memberKey] filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"SELF == %@", [event objectForKey: VXKeyIdentifier]]];

    if ([foundMembers count])
      return [calendar objectForKey: VXKeyIdentifier];
  }

  return [newEventCalendar objectForKey: VXKeyIdentifier];
}

- (NSDictionary *) readRecords {
  int i, parsedEvents;
  NSMutableDictionary *newEvent, *dictionary;
  NSDictionary *oldEvent;
  CFUUIDRef UUID;
  CFUUIDBytes uuidBytes;

  if (![self internalData] && ([self refreshInternalData] < 0))
      return nil;

  dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                [NSMutableDictionary dictionary], EntityCalendar,
                [NSMutableDictionary dictionary], EntityEvent,
                [NSMutableDictionary dictionary], EntityAudioAlarm,
                [NSMutableDictionary dictionary], EntityDisplayAlarm,
                [NSMutableDictionary dictionary], EntityRecurrence, nil];

  for (i = 0, parsedEvents = 0 ; (i < eventLimit) && (parsedEvents < eventCount) ; i++) {
    if ((usedEntries[i] & 0x01)) {
      lg_sched_event_t *event = (lg_sched_event_t *) (bytes + 2 + i * sizeof (lg_sched_event_t));
      NSDate *modificationDate = dateFromBREWLocalTime(OSSwapLittleToHostInt32(event->mtime));
      u_int32_t offset = OSSwapLittleToHostInt32 (event->offset);
      u_int32_t recurrence = OSSwapLittleToHostInt32 (event->recurrence);
      u_int32_t start_time = OSSwapLittleToHostInt32 (event->start_date);
      NSString *identifier = nil;

      parsedEvents ++;

      newEvent      = [NSMutableDictionary dictionary];
      [newEvent setObject: EntityEvent forKey: RecordEntityName];
      [newEvent setObject: [NSNumber numberWithUnsignedInt: i] forKey: VXKeyIndex];
      [newEvent setObject: dateFromBREWLocalTime (OSSwapLittleToHostInt32 (event->ctime)) forKey: VXKeyDateCreated];
      [newEvent setObject: stringFromBuffer((unsigned char *)event->summary, sizeof (event->summary), NSISOLatin1StringEncoding) forKey: @"summary"];
      [newEvent setObject: calendarDateFromLGCalendarDate (start_time) forKey: @"start date"];

      /* the index and creation date should be sufficient to uniquely identify an event on a particular phone */
      [delegate getIdentifierForRecord: newEvent compareKeys: [NSArray arrayWithObjects: VXKeyIndex, @"summary", @"start date", nil]];

      /* we might need to update the uuids of this event */
      BOOL updateUUIDs = YES;

      if (strncmp ((char *)event->extra_data, "UUID:", 5) == 0) {      
        /* we made this event (old) */
        memmove(&uuidBytes, event->extra_data+5, sizeof (CFUUIDBytes));
        UUID = CFUUIDCreateFromUUIDBytes (NULL, uuidBytes);
        identifier = (NSString *) CFUUIDCreateString (NULL, UUID);
        CFRelease (UUID);
      } else if (strlen ((char *)event->extra_data)) {
        identifier = [NSString stringWithUTF8String: (char *)event->extra_data];
        updateUUIDs = NO;
      }

      if ((OSSwapLittleToHostInt32 (event->recurrence) & 0xfe000007) == 0xfe000000) {
        /* this is a detached event */
        [newEvent setObject: [NSArray arrayWithObject: identifier] forKey: @"main event"];
        [newEvent setObject: [newEvent objectForKey: @"start date"] forKey: @"original date"];
      } else if (![[dictionary objectForKey: EntityEvent] objectForKey: identifier])
        /* haven't encountered an event with this uuid */
        [newEvent setObject: identifier forKey: VXKeyIdentifier];
      else
        /* an event exists with this uuid. it is impossible to tell if this is the original or the detached event (it has a recurrence) */
        updateUUIDs = YES;

      if (updateUUIDs) {
        /* UUID storage is finalized now */
        [identifier getCString: (char *)event->extra_data maxLength: sizeof (event->extra_data) encoding: NSASCIIStringEncoding];
        
        /* mark this entry as dirty */
        usedEntries[i] |= 0x80;
      }
      
      [newEvent setObject: [NSArray arrayWithObject: [self getCalendarIdentifierForEvent: newEvent memberKey: @"events"]] forKey: @"calendar"];    

      /* all non-static values must be changed after we setup the event from cache */
      oldEvent = [delegate findRecordWithIdentifier: [newEvent objectForKey: VXKeyIdentifier] entityName: EntityEvent];
      if (oldEvent) {
        if ([oldEvent objectForKey: @"all day"])
          [newEvent setObject: [oldEvent objectForKey: @"all day"] forKey: @"all day"];
        if ([oldEvent objectForKey: @"original date"] && [newEvent objectForKey: @"main event"])
          [newEvent setObject: [oldEvent objectForKey: @"original date"] forKey: @"original date"];
      }

      [newEvent setObject: modificationDate forKey: VXKeyDateModified];
      [newEvent setObject: calendarDateFromLGCalendarDate (OSSwapLittleToHostInt32 (event->end_date)) forKey: @"end date"];

      [self eventAlarm: event owner: newEvent storeIn: dictionary];
      [self eventRecurrence: event owner: newEvent storeIn: dictionary];

      if (recurrence & kRecurrenceExceptionBit)
        [newEvent setObject: [exceptionsData exceptionsForEvent: offset startTime: start_time] forKey: @"exception dates"];

      /* we hide an all-day flag at the end of the entry -- not anymore */
//      [newEvent setObject: [NSNumber numberWithBool: 0x01 == event->extra_data[64]] forKey: @"all day"];

      [[dictionary objectForKey: EntityEvent] setObject: newEvent forKey: [newEvent objectForKey: VXKeyIdentifier]];
    }
  }

  vxSync_log3(VXSYNC_LOG_DEBUG, @"records read from phone: %s\n", NS2CH(dictionary));
  
  /* determine main/detached events */
  for (id eventRecordIdentifier in [dictionary objectForKey: EntityEvent]) {
    NSMutableDictionary *eventRecord = [[dictionary objectForKey: EntityEvent] objectForKey: eventRecordIdentifier];

    if ([[eventRecord objectForKey: @"main event"] count]) {
      NSString *mainEventIdentifier = [[eventRecord objectForKey: @"main event"] objectAtIndex: 0];
      NSMutableDictionary *mainEvent = [[dictionary objectForKey: EntityEvent] objectForKey: mainEventIdentifier];

      if ([[mainEvent objectForKey: @"main event"] count] || !mainEvent) {
        vxSync_log3(VXSYNC_LOG_DEBUG, @"main event does not exist or relationship points to an event that has is not a main event\n");
        [eventRecord removeObjectForKey: @"main event"];
        continue;
      }
      
      if ([mainEvent objectForKey: @"detached events"])
        [[mainEvent objectForKey: @"detached events"] addObject: [eventRecord objectForKey: VXKeyIdentifier]];
      else
        [mainEvent setObject: [NSMutableArray arrayWithObject: [eventRecord objectForKey: VXKeyIdentifier]] forKey: @"detached events"];
    }
  }
  
  for (id eventRecordIdentifier in [dictionary objectForKey: EntityEvent]) {
    NSMutableDictionary *eventRecord = [[dictionary objectForKey: EntityEvent] objectForKey: eventRecordIdentifier];

    if ([[eventRecord objectForKey: @"detached events"] count]) {
      NSMutableArray *modifiedExceptions = [[[eventRecord objectForKey: @"exception dates"] mutableCopy] autorelease];
      NSMutableArray *detachedStartDates = [NSMutableArray array];

      for (id detachedIdentifier in [eventRecord objectForKey: @"detached events"]) {
        NSDictionary *detachedEvent = [[dictionary objectForKey: EntityEvent] objectForKey: detachedIdentifier];
        [detachedStartDates addObject: [detachedEvent objectForKey: @"start date"]];
      }

      [modifiedExceptions filterUsingPredicate: [NSPredicate predicateWithFormat: @"!(SELF in %@)", detachedStartDates]];
      [eventRecord removeObjectForKey: @"exception dates"];
      if ([modifiedExceptions count])
        [eventRecord setObject: modifiedExceptions forKey: @"exception dates"];
    }
  }

  [self addEventsToCalendars: dictionary];

  return [[dictionary copy] autorelease];
}

- (void) addEventsToCalendars: (NSMutableDictionary *) dict {  
  for (id calendar in intCalendars) {
    NSMutableArray *members = [NSMutableArray array];
    NSMutableDictionary *updCalendar = [[calendar mutableCopy] autorelease];
    NSString *calIdentifier = nil;
    NSArray *memberEvents;

    calIdentifier = [calendar objectForKey: VXKeyIdentifier];

    /* find member events */
    memberEvents = [[[dict objectForKey: EntityEvent] allValues] filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"(%K[FIRST] = %@)", @"calendar", calIdentifier]];

    for (id anEvent in memberEvents)
      if ([members indexOfObject: [anEvent objectForKey: VXKeyIdentifier]] == NSNotFound)
        [members addObject: [anEvent objectForKey: VXKeyIdentifier]];
    
    [updCalendar setObject: members forKey: @"events"];
    
    [[dict objectForKey: EntityCalendar] setObject: updCalendar forKey: calIdentifier];
  }
}

- (void) eventRecurrence: (lg_sched_event_t *) event owner: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) dict {
  NSMutableDictionary *newRecurrence;
  int ret;

  if (!event || !event->recurrence)
    return;

  newRecurrence = [NSMutableDictionary dictionary];
  ret = [self recurrence: OSSwapLittleToHostInt32 (event->recurrence) until: OSSwapLittleToHostInt32 (event->recurrence_end) toDict: newRecurrence];
  if (0 == ret) {
    [newRecurrence setObject: [NSArray arrayWithObject: [owner objectForKey: VXKeyIdentifier]] forKey: @"owner"];
    [delegate getIdentifierForRecord: newRecurrence compareKeys: [NSArray arrayWithObject: @"owner"]];
    
    [[dict objectForKey: EntityRecurrence] setObject: newRecurrence forKey: [newRecurrence objectForKey: VXKeyIdentifier]];
    
    [owner setObject: [NSArray arrayWithObject: [newRecurrence objectForKey: VXKeyIdentifier]] forKey: @"recurrences"];
  } else
    [owner removeObjectForKey: @"recurrences"];
}

- (int) recurrence: (u_int32_t) recurrence until: (u_int32_t) recurrence_end toDict: (NSMutableDictionary *) recurrenceRecord {
  NSMutableArray *daysOfTheWeek, *zeros;
  NSNumber *zero = [NSNumber numberWithInteger: 0];
  int i;

  switch (recurrence & 0x7) {
    case 1:
      /* daily */
      [recurrenceRecord setObject: @"daily" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: (recurrence >> 14) & 0x3f] forKey: @"interval"];
      /* XXX -- the phone may support day intervals */
      break;
    case 2:
      /* weekly */
      [recurrenceRecord setObject: @"weekly" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: (recurrence >> 14) & 0x3f] forKey: @"interval"];
      
      daysOfTheWeek = [NSMutableArray arrayWithCapacity: 7];
      zeros = [NSMutableArray arrayWithCapacity: 7];
      for (i = 0 ; i < 7 ; i++)
        if ((recurrence >> (5 + i)) & 0x1) {
          [daysOfTheWeek addObject: days[i]];
          [zeros addObject: zero];
        }
      [recurrenceRecord setObject: [NSArray arrayWithArray: daysOfTheWeek] forKey: @"bydaydays"];
      [recurrenceRecord setObject: [NSArray arrayWithArray: zeros] forKey: @"bydayfreq"];
      
      break;
    case 3:
      /* monthly */
      [recurrenceRecord setObject: @"monthly" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: (recurrence >> 14) & 0x3f] forKey: @"interval"];
      [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: (recurrence >> 25)]] forKey: @"bymonthday"];
      break;
    case 4:
      /* yearly */
      [recurrenceRecord setObject: @"yearly" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: 1] forKey: @"interval"];
      [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: (recurrence >> 14) & 0xf]] forKey: @"bymonth"];
      [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: (recurrence >> 25)]] forKey: @"bymonthday"];
      break;
    case 5:
      /* weekdays (daily recurrence on phone) */
      [recurrenceRecord setObject: @"weekly" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: 1] forKey: @"interval"];
      [recurrenceRecord setObject: [NSArray arrayWithObjects: @"monday", @"tuesday", @"wednesday", @"thursday", @"friday", nil] forKey: @"bydaydays"];
      [recurrenceRecord setObject: [NSArray arrayWithObjects: zero, zero, zero, zero, zero, nil] forKey: @"bydayfreq"];
      break;
    case 6:
      /* monthly */
      [recurrenceRecord setObject: @"monthly" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: (recurrence >> 14) & 0x3f] forKey: @"interval"];
      [recurrenceRecord setObject: [NSArray arrayWithObject: days[(recurrence >> 5) & 0x7]] forKey: @"bydaydays"];
      if ((recurrence >> 25) == 5)
        [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: -1]] forKey: @"bydayfreq"];
      else
        [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: (recurrence >> 25)]] forKey: @"bydayfreq"];
      break;
    case 7:
      /* yearly */
      [recurrenceRecord setObject: @"yearly" forKey: @"frequency"];
      [recurrenceRecord setObject: [NSNumber numberWithInteger: 1] forKey: @"interval"];
      if ((recurrence >> 25) == 5)
        [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: -1]] forKey: @"bydayfreq"]; /* last day */
      else
        [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: (recurrence >> 25)]] forKey: @"bydayfreq"];
      [recurrenceRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInteger: (recurrence >> 14) & 0xf]] forKey: @"bymonth"];
      [recurrenceRecord setObject: [NSArray arrayWithObject: days[(recurrence >> 5) & 0x7]] forKey: @"bydaydays"];
      break;
      /* bit 14 may need to be decoded eventually */
    default:
      /* unsupported recurrence */
      return -1;
  }
  
  [recurrenceRecord setObject: EntityRecurrence forKey: RecordEntityName];
  [recurrenceRecord setObject: calendarDateFromLGCalendarDate (recurrence_end) forKey: @"until"];

  [recurrenceRecord setObject: [NSNumber numberWithUnsignedInt: recurrence] forKey: VXKeyValue];
  [recurrenceRecord setObject: [NSNumber numberWithUnsignedInt: recurrence_end] forKey: VXKeyUntilValue];

  return 0;
}

- (void) eventAlarm: (lg_sched_event_t *) event owner: (NSMutableDictionary *) owner storeIn: (NSMutableDictionary *) dict {
  NSMutableDictionary *newAlarm = [NSMutableDictionary dictionary];
  NSString *entityName;
  int hours, mins;

  /* no alarm */
  if (!event || !(event->alarm & 0xfe)) {
    [owner removeObjectForKey: @"audio alarms"];
    [owner removeObjectForKey: @"display alarms"];
    /* the audible alarm bit can be set even if there is no reminder */
    return;
  }

  entityName = (event->alarm & 0x01) ? EntityAudioAlarm : EntityDisplayAlarm;
  
  [newAlarm setObject: entityName forKey: RecordEntityName];
  if (event->alarm & 0x01)
    [newAlarm setObject: @"Basso" forKey: @"sound"]; /* I may be able to get the ringtone as the alarm using com.apple.ical.sound */

  hours = (0xff == event->hours_before) ? 0 : event->hours_before;
  mins  = (0xff == event->minutes_before) ? 0 : event->minutes_before;

  [newAlarm setObject: [NSNumber numberWithInteger: - (hours * 60 + mins) * 60] forKey: @"triggerduration"];
  [newAlarm setObject: [NSNumber numberWithInteger: event->alarm]  forKey: VXKeyValue];
  [newAlarm setObject: [NSArray arrayWithObject: [owner objectForKey: VXKeyIdentifier]] forKey: @"owner"];

  [delegate getIdentifierForRecord: newAlarm compareKeys: [NSArray arrayWithObject: @"owner"]];
  [owner setObject: [NSArray arrayWithObject: [newAlarm objectForKey: VXKeyIdentifier]] forKey: [entityName isEqual: EntityAudioAlarm] ? @"audio alarms" : @"display alarms"];

  [[dict objectForKey: entityName] setObject: newAlarm forKey: [newAlarm objectForKey: VXKeyIdentifier]];
}


- (int) setEvent: (NSDictionary *) eventRecord formattedRecordOut: (NSDictionary **) recordOut atIndex: (u_int32_t) eventIndex isNew: (BOOL) isNew identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord;
  NSMutableSet *effectiveExceptions = [NSMutableSet set];
  u_int32_t offset = 2 + eventIndex * sizeof (lg_sched_event_t);

  lg_sched_event_t *event = (lg_sched_event_t *)(bytes + offset);
  id formattedRelation = nil;

  if (isNew)
    memset (event, 0, sizeof (lg_sched_event_t));

  /* inform VXSyncDataSource of our changes */
  formattedRecord = [[eventRecord mutableCopy] autorelease];
  [formattedRecord setObject: [NSNumber numberWithInteger: eventIndex] forKey: VXKeyIndex];
  *recordOut = formattedRecord;

  event->offset = OSSwapHostToLittleInt32 (offset);

  [[eventRecord objectForKey: @"summary"] getCString: event->summary maxLength: sizeof (event->summary) encoding: NSISOLatin1StringEncoding];

  event->ctime = OSSwapHostToLittleInt32 (BREWLocalTimeFromDate ([eventRecord objectForKey: VXKeyDateCreated]));
  event->mtime = OSSwapHostToLittleInt32 (BREWLocalTimeFromDate ([eventRecord objectForKey: VXKeyDateModified]));

//  if ([[eventRecord objectForKey: @"all day"] boolValue])
//    event->extra_data[64] = 0x01;
  
  event->start_date = OSSwapLittleToHostInt32 (LGCalendarDateFromDate ([eventRecord objectForKey: @"start date"]));
  event->end_date = OSSwapLittleToHostInt32 (LGCalendarDateFromDate ([eventRecord objectForKey: @"end date"]));

  /* this value varied between phones but it doesn't appear that it matters */
  event->unknown3 = OSSwapHostToLittleInt16(0x1fa);

  /* UUID storage is finalized */
  if ([[eventRecord objectForKey: @"main event"] count])
    [[[eventRecord objectForKey: @"main event"] objectAtIndex: 0] getCString: (char *) event->extra_data maxLength: sizeof (event->extra_data) encoding: NSASCIIStringEncoding];
  else
    [identifier getCString: (char *) event->extra_data maxLength: sizeof (event->extra_data) encoding: NSASCIIStringEncoding];
  
  /* it is easier to remove the exceptions the readd them */
  if ([[eventRecord objectForKey: @"exception dates"] count])
    [effectiveExceptions addObjectsFromArray: [eventRecord objectForKey: @"exception dates"]];
  
  for (id detachedIdentifier in [eventRecord objectForKey: @"detached events"]) {
    NSDictionary *detachedEvent = [delegate findRecordWithIdentifier: detachedIdentifier entityName: EntityEvent];
    [effectiveExceptions addObject: [detachedEvent objectForKey: @"start date"]];
  }
  
  if ([effectiveExceptions count]) {
    event->recurrence = OSSwapHostToLittleInt32(kRecurrenceExceptionBit);
    [exceptionsData addExceptionsFromArray: [effectiveExceptions allObjects] eventID: offset];
  }
  
  /* unset onphone for all related records */
  for (id tmpIdentifier in [eventRecord objectForKey: @"audio alarms"]) {
    NSMutableDictionary *tmpAlarmRecord = [[delegate findRecordWithIdentifier: tmpIdentifier entityName: EntityAudioAlarm] mutableCopy];
    [tmpAlarmRecord setObject: [NSNumber numberWithBool: NO] forKey: VXKeyOnPhone];
    [delegate modifyRecord: tmpAlarmRecord withIdentifier: tmpIdentifier withEntityName: EntityAudioAlarm];
  }

  for (id tmpIdentifier in [eventRecord objectForKey: @"display alarms"]) {
    NSMutableDictionary *tmpAlarmRecord = [[delegate findRecordWithIdentifier: tmpIdentifier entityName: EntityDisplayAlarm] mutableCopy];
    [tmpAlarmRecord setObject: [NSNumber numberWithBool: NO] forKey: VXKeyOnPhone];
    [delegate modifyRecord: tmpAlarmRecord withIdentifier: tmpIdentifier withEntityName: EntityDisplayAlarm];
  }

  /* set recurrence */
  id recurrenceIdentifier = [[eventRecord objectForKey: @"recurrences"] objectAtIndex: 0];
  id recurrenceRecord     = [delegate findRecordWithIdentifier: recurrenceIdentifier entityName: EntityRecurrence];

  [self setRecurrenceForEvent: formattedRecord to: recurrenceRecord formattedRecordOut: &formattedRelation identifier: recurrenceIdentifier];
  if (formattedRelation)
    [delegate modifyRecord: formattedRelation withIdentifier: recurrenceIdentifier withEntityName: EntityRecurrence];
  
  /* set alarm */
  id alarmIdentifier = [[eventRecord objectForKey: @"audio alarms"] objectAtIndex: 0];
  id alarmRecord     = [delegate findRecordWithIdentifier: alarmIdentifier entityName: EntityAudioAlarm];
  if (!alarmIdentifier) {
    alarmIdentifier = [[eventRecord objectForKey: @"display alarms"] objectAtIndex: 0];
    alarmRecord = [delegate findRecordWithIdentifier: alarmIdentifier entityName: EntityDisplayAlarm];
  }

  /* this will unset the alarm if alarmRecord is nil */
  formattedRelation = nil;
  [self setAlarmForEvent: formattedRecord to: alarmRecord formattedRecordOut: &formattedRelation identifier: alarmIdentifier];

  if ([[formattedRelation objectForKey: RecordEntityName] isEqual: EntityDisplayAlarm])
    [delegate modifyRecord: formattedRelation withIdentifier: alarmIdentifier withEntityName: EntityDisplayAlarm];
  else if (formattedRelation)
    [delegate modifyRecord: formattedRelation withIdentifier: alarmIdentifier withEntityName: EntityAudioAlarm];

  if (isNew)
    OSWriteLittleInt16 (bytes, 0, ++eventCount);
  
  /* mark this entry as used */
  usedEntries[eventIndex] = 0x81;

  return 0;
}

- (NSDictionary *) formatEvent: (NSDictionary *) eventRecord identifier: (NSString *) identifier {
  NSMutableDictionary *formattedRecord = [eventRecord mutableCopy];
  NSCalendarDate *startDate, *endDate;

  /* truncate the summary value */
  [formattedRecord setObject: shortenString([formattedRecord objectForKey: @"summary"], NSISOLatin1StringEncoding, 33) forKey: @"summary"];

  /* don't know the creation date. set it here. */
  if (![formattedRecord objectForKey: VXKeyDateCreated])
    [formattedRecord setObject: [NSDate date] forKey: VXKeyDateModified];

  [formattedRecord setObject: [NSDate date] forKey: VXKeyDateCreated];
  
  if ([[formattedRecord objectForKey: @"all day"] boolValue]) {
    startDate = [eventRecord objectForKey: @"start date"];
    endDate   = [eventRecord objectForKey: @"end date"];

    [startDate setTimeZone: [NSTimeZone localTimeZone]];
    [endDate setTimeZone: [NSTimeZone localTimeZone]];
    
    /* all day events go from noon on the start day to noon on the next for some bizzare reason */
    startDate = [startDate dateByAddingYears: 0
                                      months: 0
                                        days: 0
                                       hours: -[startDate hourOfDay]
                                     minutes: -[startDate minuteOfHour]
                                     seconds: -[startDate secondOfMinute]];
    /* end at the end of the day */
    endDate = [endDate dateByAddingYears: 0
                                  months: 0
                                    days: 0
                                   hours: -[endDate hourOfDay]
                                 minutes: -([endDate minuteOfHour] + 1)
                                 seconds: -[endDate secondOfMinute]];
    
    /* inform sync services of our view of an all-day event */
    [formattedRecord setObject: startDate forKey: @"start date"];
    [formattedRecord setObject: endDate forKey: @"end date"];
  }
  
  return [[formattedRecord copy] autorelease];
}

- (int) setAlarmForEvent: (NSDictionary *) event to: (NSDictionary *) alarmRecord formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  u_int32_t eventIndex = [[event objectForKey: VXKeyIndex] integerValue];
  u_int32_t offset = 2 + eventIndex * sizeof (lg_sched_event_t);
  lg_sched_event_t *lgEvent = (lg_sched_event_t *)(bytes + offset);
  NSMutableDictionary *formattedAlarm = [[alarmRecord mutableCopy] autorelease];

  if (alarmRecord) {
    int seconds    = -[[alarmRecord objectForKey: @"triggerduration"] integerValue];
    int alarmValue = [[alarmRecord objectForKey: VXKeyValue] integerValue];
    
    lgEvent->minutes_before = (seconds / 60) % 60;
    lgEvent->hours_before   = (seconds / 3600);
    lgEvent->alarm          = alarmValue;

    [formattedAlarm setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];

    /* no changes were made to this record */
    *recordOut = formattedAlarm;
  } else {
    lgEvent->minutes_before = 0x64;
    lgEvent->hours_before   = 0x64;
    lgEvent->alarm          = 0x01;
    lgEvent->ringtone_index = noRingIndex;
  }

  /* mark event as modified */
  usedEntries[eventIndex] |= 0x80;

  return 0;
}

- (NSDictionary *) formatAlarm: (NSDictionary *) alarmRecord identifier: (NSString *) identifier {
  int supportedAlarmSeconds[] = {0, 0, 300, 600, 900, 1800, 3600, 10800, 18000, 86400, -1};
  NSMutableDictionary *formattedRecord = [NSMutableDictionary dictionaryWithDictionary: alarmRecord];
  int i, seconds, alarmValue;

  seconds = -[[alarmRecord objectForKey: @"triggerduration"] integerValue];
  
  /* LG phones support only a limited # of trigger durations */
  for (i = 0 ; i < 10 ; i++)
    if (abs (seconds - supportedAlarmSeconds[i]) < abs (seconds - supportedAlarmSeconds[i+1]))
      break;

  i = (i == 10) ? 9 : i;
  seconds = supportedAlarmSeconds[i];
  alarmValue = [[alarmRecord objectForKey: RecordEntityName] isEqualToString: EntityAudioAlarm] | (i << 1);

  /* tell sync services that we will be using a different number of seconds for the duration */
  [formattedRecord setObject: [NSNumber numberWithInteger: - seconds] forKey: @"triggerduration"];
  [formattedRecord setObject: [NSNumber numberWithInteger: alarmValue] forKey: VXKeyValue];
  
  return [[formattedRecord copy] autorelease];
}

- (int) setRecurrenceForEvent: (NSDictionary *) event to: (NSDictionary *) recurrenceRecord formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  u_int32_t eventIndex = [[event objectForKey: VXKeyIndex] integerValue];
  u_int32_t offset = 2 + eventIndex * sizeof (lg_sched_event_t);
  u_int32_t recurrence, recurrence_end;
  NSMutableDictionary *formattedRecord;

  lg_sched_event_t *lgEvent = (lg_sched_event_t *)(bytes + offset);
  
  if ([[event objectForKey: @"main event"] count]) {
    /* detached events can't be recurrent. the phone sets this flag to signal detached events */
    recurrence     = 0xfe000000;
    recurrence_end = 0;
  } else {
    recurrence     = [[recurrenceRecord objectForKey: VXKeyValue] unsignedIntValue] | OSSwapHostToLittleInt32((lgEvent->recurrence & OSSwapHostToLittleInt32 (kRecurrenceExceptionBit)));
    recurrence_end = [[recurrenceRecord objectForKey: VXKeyUntilValue] unsignedIntValue];
  }

  lgEvent->recurrence_end = OSSwapHostToLittleInt32 (recurrence_end);
  lgEvent->recurrence     = OSSwapHostToLittleInt32 (recurrence);

  vxSync_log3(VXSYNC_LOG_DEBUG, @"recurrence = %08x, recurrence record = %s\n", recurrence, NS2CH(recurrenceRecord));
  
  if (recordOut) {
    /* create a formatted record for this recurrence */
    formattedRecord = [[recurrenceRecord mutableCopy] autorelease];
    [formattedRecord setObject: [NSNumber numberWithUnsignedInt: recurrence] forKey: VXKeyValue];
    [formattedRecord setObject: [NSNumber numberWithBool: YES] forKey: VXKeyOnPhone];

    *recordOut = [[formattedRecord copy] autorelease];
  }
  
  vxSync_log3_data(VXSYNC_LOG_DEBUG, [NSData dataWithBytes: lgEvent length: sizeof (lg_sched_event_t)], @"after setting recurrence:\n");

  /* mark event as modified */
  usedEntries[eventIndex] |= 0x80;

  return 0;
}

- (NSDictionary *) formatRecurrence: (NSDictionary *) recurrenceRecord identifier: (NSString *) identifier {
  u_int32_t recurrence = 0, recurrence_end = 0;
  NSMutableDictionary *formattedRecord;
  NSDictionary *event = [delegate findRecordWithIdentifier: [[recurrenceRecord objectForKey: @"owner"] objectAtIndex: 0] entityName: EntityEvent];
  NSDate *startDate = [event objectForKey: @"start date"];
  NSDateComponents *startComp = [[NSCalendar currentCalendar] components: NSMonthCalendarUnit | NSWeekCalendarUnit | NSWeekdayCalendarUnit | NSDayCalendarUnit fromDate: startDate];
  NSCalendarDate *until = [recurrenceRecord objectForKey: @"until"];

  if (!until) 
    /* default recurrence end for LG phones (5 years from now) */
    until = [[startDate dateWithCalendarFormat: nil timeZone: nil] dateByAddingYears: 5 months: 0 days: 0 hours: 0 minutes: 0 seconds: 0];

  vxSync_log3(VXSYNC_LOG_DEBUG, @"formatting recurrence: %s\n", NS2CH(recurrenceRecord));
  
  if ([[recurrenceRecord objectForKey: RecordEntityName] isEqualToString: EntityRecurrence]) {  
    int interval   = [[recurrenceRecord objectForKey: @"interval"] integerValue];
    NSString *frequency  = [recurrenceRecord objectForKey: @"frequency"];
    NSArray *bydaydays  = [recurrenceRecord objectForKey: @"bydaydays"];
    NSArray *bydayfreq  = [recurrenceRecord objectForKey: @"bydayfreq"];
    NSArray *bymonth    = [recurrenceRecord objectForKey: @"bymonth"];
    NSArray *bymonthday = [recurrenceRecord objectForKey: @"bymonthday"];
    int i, day, month;
    
    if (interval > 0x3f)
      interval = 0x3f;
    
    if ([frequency isEqualToString: @"daily"]) {
      recurrence  = 0x00000001 | (interval << 14);
    } else if ([frequency isEqualToString: @"weekly"]) {
      if ([bydaydays count] == 5 && (NSInteger)[bydaydays indexOfObject: @"saturday"] == NSNotFound && (NSInteger)[bydaydays indexOfObject: @"sunday"] == NSNotFound && interval == 1) {
        recurrence = 0x00000005 | (interval << 14);
      } else {
        recurrence = 0x00000002 | (interval << 14);
        if ([bydaydays count]) {
          for (i = 0 ; i < 7 ; i++)
            if (NSNotFound != [bydaydays indexOfObject: days[i]])
              recurrence |= 1 << (5 + i);
        } else
        /* simple weekly */
          recurrence |= 1 << (4 + [startComp weekday]);
      }
    } else if ([frequency isEqualToString: @"monthly"]) {
      if ([bydaydays count]) {
        day = [[bydayfreq objectAtIndex: 0] integerValue];

        /* invalid recurrence */
        if (day > 4) {
          [formattedRecord setObject: [NSArray arrayWithObject: [NSNumber numberWithInt: -1]] forKey: @"bydayfreq"];
          day = -1;
        }

        for (i = 0 ; i < 7 ; i++)
          if ([[bydaydays objectAtIndex: 0] isEqualToString: days[i]])
            break;
        
        recurrence = 0x00000006 | (interval << 14) | (((day != -1) ? day : 5) << 25) | (i << 5);
      } else {
        day = [bymonthday count] ? [[bymonthday objectAtIndex: 0] integerValue] : [startComp day];
        
        recurrence = 0x00000003 | (interval << 14) | (day << 25);
      }
    } else if ([frequency isEqualToString: @"yearly"]) {    
      if ([bymonthday count] || ![bydayfreq count]) {
        /* day of the month or simple yearly */
        day   = bymonthday ? [[bymonthday objectAtIndex: 0] integerValue] : [startComp day];
        month = bymonthday ? [[bymonth objectAtIndex: 0] integerValue] : [startComp month];
        
        recurrence = 0x00000004 | (month << 14) | (day << 25);
      } else if ([bydayfreq count]) {
        day   = [[bydayfreq objectAtIndex: 0] integerValue];
        month = [[bymonth objectAtIndex: 0] integerValue];
        
        if (day == -1) day = 5;
        for (i = 0 ; i < 7 ; i++)
          if ([[bydaydays objectAtIndex: 0] isEqualToString: days[i]])
            break;
        
        recurrence = 0x00000007 | (day << 25) | (month << 14) | (i << 5);
      }
    }
    
    vxSync_log3(VXSYNC_LOG_DEBUG, @"**** recurrence end date: %s, recurrence = %08x\n", NS2CH(until), recurrence);
    
    recurrence_end = (recurrence & 0x7) ? LGCalendarDateFromDate (until) : 0;
  }

  formattedRecord = [[recurrenceRecord mutableCopy] autorelease];
  [self recurrence: recurrence until: recurrence_end toDict: formattedRecord];

  return [[formattedRecord copy] autorelease];
}

- (int) addOrModifyRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew {
  NSString *entityName = [record objectForKey: RecordEntityName];
  NSDictionary *event;
  int i;
  
  *recordOut = nil;

  if ([entityName isEqualToString: EntityEvent]) {
    if (isNew) {
      for (i = 0 ; i < eventLimit ; i++)
        if (!(usedEntries[i] & 0x01))
          break;

      if (i == eventLimit)
      /* no space left for event */
        return -3;
    } else
      i = [[record objectForKey: VXKeyIndex] integerValue];

    /* this entity belongs to a calendar we sync with */
    return [self setEvent: record formattedRecordOut: recordOut atIndex: i isNew: isNew identifier: identifier];
  } else if ([entityName isEqualToString: EntityCalendar]) {
    NSMutableDictionary *newRecord = [[record mutableCopy] autorelease];
    [newRecord setObject: identifier forKey: VXKeyIdentifier];
    
    *recordOut = [newRecord copy];
    
    [intCalendars filterUsingPredicate: [NSPredicate predicateWithFormat: @"%K != %@", VXKeyIdentifier, identifier]];
    [intCalendars addObject: newRecord];
    
    return 0;
  }

  /* locate the entity associated with this event */
  event = [delegate findRecordWithIdentifier: [[record objectForKey: @"owner"] objectAtIndex: 0] entityName: EntityEvent];
  if (event) {
    /* is it possible to get the recurrence/alarm before the event? if so we need to account for that senario */
    if ([entityName isEqualToString: EntityAudioAlarm] || [entityName isEqualToString: EntityDisplayAlarm])
      return [self setAlarmForEvent: event to: record formattedRecordOut: recordOut identifier: identifier];
    else if ([entityName isEqualToString: EntityRecurrence])
      return [self setRecurrenceForEvent: event to: record formattedRecordOut: recordOut identifier: identifier];
  }

  /* unsupported entity or event not found */
  return -2;
}

- (NSDictionary *) formatRecord: (NSDictionary *) record identifier: (NSString *) identifier {
  NSString *entityName = [record objectForKey: RecordEntityName];
  if ([entityName isEqual: EntityEvent])
    return [self formatEvent: record identifier: identifier];
  else if ([entityName isEqual: EntityRecurrence])
    return [self formatRecurrence: record identifier: identifier];
  else if ([entityName isEqual: EntityAudioAlarm] || [entityName isEqual: EntityDisplayAlarm])
    return [self formatAlarm: record identifier: identifier];
  else if ([entityName isEqual: EntityCalendar])
    return record; /* don't format the calendar */

  return nil; /* entity not supported */
}

- (int) addRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  return [self addOrModifyRecord: record formattedRecordOut: recordOut identifier: identifier isNew: YES];
}

- (int) modifyRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  return [self addOrModifyRecord: record formattedRecordOut: recordOut identifier: identifier isNew: NO];
}

- (BOOL) deleteAllRecordsForEntityName: (NSString *) entityName {
  /* there shouldn't be a need to support deleting all recurrences or alarms imho */
  if (!([entityName isEqual: EntityEvent] || [entityName isEqual: EntityCalendar]))
    return NO;
  
  /* need to determine what events are already on the phone before attempting to clear them */
  if (!internalData && [self refreshInternalData] == -1)
    return NO;

  if ([entityName isEqual: EntityCalendar]) {
    [[phone efs] unlink: @"sch/isynccalendars.plist"];
    [self setIntCalendars: [NSMutableArray array]];
    
    return YES;
  }
  
  [self setInternalData: [NSMutableData dataWithLength: 2 + eventLimit * sizeof (lg_sched_event_t)]];

  bytes      = [internalData mutableBytes];
  eventCount = 0;

  memset (bytes + 2, 0xff, 2 + eventLimit * sizeof (lg_sched_event_t));

  for (int i = 0 ; i < eventLimit ; i++)
    if (usedEntries[i] & 0x01)
      usedEntries[i] = 0x80;

  return YES;
}

- (BOOL) deleteAllRecords {
  vxSync_log3(VXSYNC_LOG_INFO, @"deleting all records");

  [self deleteAllRecordsForEntityName: EntityEvent];
  [self deleteAllRecordsForEntityName: EntityCalendar];

  [exceptionsData removeAllExceptions];
  
  return YES;
}

- (int) deleteRecord: (NSDictionary *) record {
  NSString *entityName = [record objectForKey: RecordEntityName];
  u_int32_t offset, eventIndex;
  lg_sched_event_t *lgevent;
 
  if (![entityName isEqualToString: EntityEvent]) {
    id entry;
    
    if ([entityName isEqualToString: EntityCalendar]) {
      [intCalendars filterUsingPredicate: [NSPredicate predicateWithFormat: @"%K != %@", VXKeyIdentifier, [record objectForKey: VXKeyIdentifier]]];
      return 0;
    }
    
    /* locate the entity associated with this event -- it might have been deleted earlier */
    entry = [delegate findRecordWithIdentifier: [[record objectForKey: @"owner"] objectAtIndex: 0] entityName: EntityContact];
    
    if (entry) {
      if ([entityName isEqualToString: EntityAudioAlarm] || [entityName isEqualToString: EntityDisplayAlarm])
        return [self setAlarmForEvent: entry to: nil formattedRecordOut: nil identifier: nil];
      else if ([entityName isEqualToString: EntityRecurrence])
        return [self setRecurrenceForEvent: entry to: nil formattedRecordOut: nil identifier: nil];
    }
    
    return 0;
  }
  
  /* delete an event */
  eventIndex = [[record objectForKey: VXKeyIndex] unsignedIntValue];
  offset     = 2 + eventIndex * sizeof (lg_sched_event_t);
  
  /* delete exceptions for this event */
  [exceptionsData removeExeptionsForEvent: offset];
  
  lgevent = (lg_sched_event_t *)(bytes + offset);
  
  /* mark the entry as invalid */
  memset (lgevent, 0xff, sizeof (lg_sched_event_t));
  
  /* update the event count */
  OSWriteLittleInt16 (bytes, 0, (0 == eventCount) ? 0 : --eventCount);

  /* mark the entry as available */
  usedEntries[eventIndex] = 0x80;
  
  return 0;
}

- (int) refreshInternalCalendars {  
  @try {
    NSData *plistData =  [[phone efs] get_file_data_from: @"sch/isynccalendars.plist" errorOut: nil];
    if (!plistData)
      [NSException raise: @"fileError" format: @"unable to read from sch/isynccalendars.plist. assuming vxSync has not been used with phone"];
    NSString *error;
    NSPropertyListFormat format;
    id plist = [NSPropertyListSerialization propertyListFromData: plistData mutabilityOption: 0 format: &format errorDescription: &error];
    
    if (!plist)
      [NSException raise: @"plistError" format: @"unable to create plist of calendar data: error = %@\n", error];

    [self setIntCalendars: [NSMutableArray arrayWithArray: (NSArray *)plist]];
  } @catch (NSException *e) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"non-fatal: could not read calendars from phone: %s\n", NS2CH([e reason]));
    [self setIntCalendars: [NSMutableArray array]];
  }
  
  /* get calendar */
  ISyncRecordSnapshot *snapshot = [[[delegate sessionDriver] session] snapshotOfRecordsInTruth];
  @try {
    NSDictionary *calendar = [snapshot recordsWithMatchingAttributes: [NSDictionary dictionaryWithObjectsAndKeys: newEventCalendarTitle, @"title", EntityCalendar, ISyncRecordEntityNameKey, nil]];
    if (!calendar) {
      NSArray *foo = [intCalendars filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"title = %@", newEventCalendarTitle]];
      
      if (![foo count])
        foo = [intCalendars filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"title = %@", [newEventCalendarTitle stringByAppendingFormat: @" - vxSync"]]];
      
      if ([foo count])
        [self setNewEventCalendar: [foo objectAtIndex: 0]];
    } else
      [self setNewEventCalendar: [NSDictionary dictionaryWithObjectsAndKeys: newEventCalendarTitle, @"title", EntityCalendar, ISyncRecordEntityNameKey, [[calendar allKeys] objectAtIndex: 0], VXKeyIdentifier, nil]];
  } @catch (NSException *e) {
    vxSync_log3(VXSYNC_LOG_INFO, @"calendar datasource will create a new calendar since no calendar snapshot available: %s\n", NS2CH(e));
  }
  
  if (![self newEventCalendar]) {
    NSMutableDictionary *_newEventCalendar = [NSMutableDictionary dictionaryWithObjectsAndKeys: [newEventCalendarTitle stringByAppendingFormat: @" - vxSync"], @"title", EntityCalendar, ISyncRecordEntityNameKey, nil];
    [delegate getIdentifierForRecord: _newEventCalendar compareKeys: [NSArray arrayWithObjects: @"title", nil]];
    [self setNewEventCalendar: _newEventCalendar];
  }
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"new event calendar: %s\n", NS2CH(newEventCalendar));
  
  [intCalendars addObject: newEventCalendar];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"intCalendars = %s\n", NS2CH(intCalendars));
  
  return 0;
}

- (int) commitCalendars {
  NSData *plistData;
  NSString *error;
  int ret;
  
  if (!intCalendars)
    return -1;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"commiting calendar changes...\n");

  plistData = [NSPropertyListSerialization dataFromPropertyList: intCalendars format: NSPropertyListBinaryFormat_v1_0 errorDescription: &error];
  if (!plistData) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not create property list. error: %s\n", NS2CH(error));
    return -1;
  }
  
  ret = [[phone efs] write_file_data: plistData to:@"sch/isynccalendars.plist"];
  return (ret > 0) ? 0 : -1;
}

- (int) commitSchedule {
  int i, fd;

  vxSync_log3(VXSYNC_LOG_INFO, @"commiting schedule changes...\n");
  
  fd = [[phone efs] open: VXSchedulePath withFlags: O_RDWR];
  if (-1 == fd)
    return -1;
  
  [[phone efs] write: fd from: bytes count: 2];
  for (i = 0 ; i < eventLimit ; i++) {
    int offset = 2 + i * sizeof (lg_sched_event_t);
    
    if (usedEntries[i] & 0x80) {
      [[phone efs] lseek: fd toOffset: offset whence: SEEK_SET];
      [[phone efs] write: fd from: bytes + offset count: sizeof (lg_sched_event_t)];
    }
    
    usedEntries[i] &= 0x7f;
  }
  
  [[phone efs] close: fd];
  
  return 0;
}

- (int) commitChanges {
  if (!internalData)
    return 0;
  
  (void) [exceptionsData commitChanges];
  (void) [self commitCalendars];
  (void) [self commitSchedule];

  return 0;
}

@end
