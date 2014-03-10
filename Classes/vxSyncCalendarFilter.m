/* (-*- objc -*-)
 * vxSync: vxSyncCalendarFilter.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.6.3 - July 11, 2010
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

#include "vxSyncCalendarFilter.h"
#include <CalendarStore/CalendarStore.h>

@implementation vxSyncCalendarFilter

#pragma mark properties
@synthesize calendarTitles, clientIdentifier, snapshot;

#pragma mark allocation/deallocation

+ (vxSyncCalendarFilter *) filter {
  return [[[vxSyncCalendarFilter alloc] init] autorelease];
}

- (id) init {
  return [super init];
}

- (void) dealloc {
  [self setCalendarTitles: nil];
  [self setClientIdentifier: nil];
  [self setSnapshot: nil];
  [super dealloc];
}

#pragma mark ISyncFiltering

- (NSArray *) supportedEntityNames {
  return [NSArray arrayWithObjects: EntityCalendar, EntityEvent, EntityAudioAlarm, EntityDisplayAlarm, EntityRecurrence, nil];
}

- (BOOL) shouldApplyRecord: (NSDictionary *) record withRecordIdentifier: (NSString *) recordIdentifier {
  NSDictionary *calendarRecord;
  NSString *title;

  if (![[record objectForKey: RecordEntityName] isEqual: EntityCalendar]) {
    NSDictionary *calendarRecords, *eventRecord;
    
    if (!snapshot)
      [self setSnapshot: [[ISyncManager sharedManager] snapshotOfRecordsInTruthWithEntityNames: [NSArray arrayWithObjects: EntityCalendar, EntityEvent, nil] usingIdentifiersForClient: [[ISyncManager sharedManager] clientWithIdentifier: clientIdentifier]]];

    if (![[record objectForKey: RecordEntityName] isEqual: EntityEvent]) {
      NSDictionary *eventRecords = [snapshot recordsWithIdentifiers: [record objectForKey: @"owner"]];
      
      if ([eventRecords count])
        eventRecord = [eventRecords objectForKey: [[eventRecords allKeys] objectAtIndex: 0]];
    } else
      eventRecord = record;

    calendarRecords = [snapshot recordsWithIdentifiers: [eventRecord objectForKey: @"calendar"]];
        
    if ([calendarRecords count])
      calendarRecord = [calendarRecords objectForKey: [[calendarRecords allKeys] objectAtIndex: 0]];
  } else
    calendarRecord = record;
    
  if ([[calendarRecord objectForKey: @"com.apple.ical.type"] isEqualToString: @"caldav"])
    title = [[[calendarRecord objectForKey: @"title"] componentsSeparatedByString: @"["] objectAtIndex: 0];
  else
    title = [calendarRecord objectForKey: @"title"];

  return ([calendarTitles indexOfObject: title] != NSNotFound);
}

- (BOOL) isEqual: (id) anotherFilter {  
  if ([anotherFilter respondsToSelector: @selector(calendarTitles)])
    return [calendarTitles isEqual: [anotherFilter calendarTitles]];
  
  return NO;
}

#pragma mark NSCoding
- (id)initWithCoder:(NSCoder *)coder {
  if ( [coder allowsKeyedCoding] ) {
    [self setCalendarTitles: [coder decodeObjectForKey:@"calendarTitles"]];
    [self setClientIdentifier: [coder decodeObjectForKey:@"clientIdentifier"]];
  } else {
    [self setCalendarTitles: [coder decodeObject]];
    [self setClientIdentifier: [coder decodeObject]];
  }
  
  snapshot = nil;
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  if ([coder allowsKeyedCoding]) {
    [coder encodeObject:calendarTitles forKey:@"calendarTitles"];
    [coder encodeObject:clientIdentifier forKey:@"clientIdentifier"];
  } else {
    [coder encodeObject:calendarTitles];
    [coder encodeObject:clientIdentifier];
  }

  return;
}

@end
