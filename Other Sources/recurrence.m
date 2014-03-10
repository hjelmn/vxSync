#include "VXSync.h"

NSString *days[] = {nil, @"sunday", @"monday", @"tuesday", @"wednesday", @"thursday", @"friday", @"saturday"};

#define kSecondsInDay   86400
#define kSecondsInWeek 604800

static NSArray *daysToWeekdays (NSArray *bydaydays) {
  if (nil == bydaydays)
    return nil;

  NSMutableArray *ordinals = [NSMutableArray arrayWithCapacity: [bydaydays count]];
  int i = 0;
  NSEnumerator *bydaydaysEnum = [bydaydays objectEnumerator];
  id day;

  while ((day = [bydaydaysEnum nextObject])) {
    while (i < 8 && ![days[i] isEqualToString: day]) i++;
    
    [ordinals addObject: [NSNumber numberWithInt: i]];
  }

  return [[ordinals copy] autorelease];
}

static int checkOccurrence (NSDate **occurrenceStore, NSDate *occurrenceDate, NSSet *exceptions, NSDate *until, int *countp, NSDate *startDate, NSDate *after) {
  int count = countp ? *countp : -1;
  vxSync_log3(VXSYNC_LOG_INFO, @"occurrence (%s, %s, %s, %s, %i, %s, %s)\n", NS2CH(*occurrenceStore), NS2CH(occurrenceDate), NS2CH(exceptions), NS2CH(until),
              count, NS2CH(startDate), NS2CH(after));

  if ((until && ([until compare: occurrenceDate] == NSOrderedAscending)) || (count == 0))
    /* done */
    return -1;

  if ((exceptions && [exceptions containsObject: occurrenceDate]) || ([startDate compare: occurrenceDate] == NSOrderedDescending))
    /* either an exception or */
    return 0;

  if (!after || !*occurrenceStore || (*occurrenceStore && [(*occurrenceStore) compare: after] == NSOrderedAscending))
    *occurrenceStore = occurrenceDate;
  
  if (countp && *countp > 0)
    (*countp)--;
  
  if (after && (*occurrenceStore) && [(*occurrenceStore) compare: after] == NSOrderedDescending)
    /* done */
    return -1;

  return 1;
}

/* Get either the closest occurence to closestTo or the last occurrence */
NSDate *getAnOccurrence (NSDictionary *event, NSDictionary *recurrence, NSDate *after) {
  NSDate *startDate   = [event objectForKey: @"start date"];
  NSDate *occurrenceDate = nil, *foundOccurrence = nil;
  int count = -1;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"finding occurrences of event %s with recurrence %s\n", NS2CH(event), NS2CH(recurrence));
  
  /* only one occurrence */
  if (![event objectForKey: @"recurrences"])
    return startDate;

  if (!recurrence)
    return nil;
  
  NSSet *exceptions = [NSSet setWithArray: [event objectForKey: @"exception dates"]];
  NSDate *until       = [recurrence objectForKey: @"until"];
  NSString *frequency = [recurrence objectForKey: @"frequency"];
  int interval        = [[recurrence objectForKey: @"interval"] intValue];
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSCalendarUnit units;
  NSDateComponents *comps, *testComps, *advComps = [[[NSDateComponents alloc] init] autorelease];
  int i, ret;

  /* sanity check -- interval CAN NOT be 0 */
  if (0 == interval) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"recurrence interval is 0!\n");
    return nil;
  }
  
  /* sanity check -- until date can not be before start date */
  if (until && ([until compare: startDate] == NSOrderedAscending)) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"recurrence until date is before the event start date!\n");
    return nil;
  }

  if (!until)
    count = [[recurrence objectForKey: @"count"] intValue] ? [[recurrence objectForKey: @"count"] intValue] - [exceptions count] : -1;
  
  if (!until && (count < 1)) {
    [advComps setYear: 5];
    until = [cal dateByAddingComponents: advComps toDate: startDate options: 0];
    advComps = [[[NSDateComponents alloc] init] autorelease];
  }
  
  ret = checkOccurrence (&foundOccurrence, startDate, exceptions, until, &count, startDate, after);
  if (-1 == ret) {
    vxSync_log3(VXSYNC_LOG_INFO, @"returning: %s\n", NS2CH(foundOccurrence));

    return foundOccurrence;
  }
  
  if ([[recurrence objectForKey: @"bymonth"] count] && [frequency isEqualToString: @"monthly"])
    frequency = @"yearly";

  if ([frequency isEqualToString: @"yearly"]) {
    NSArray *bymonth = [recurrence objectForKey: @"bymonth"];
    NSArray *weekdays = daysToWeekdays ([recurrence objectForKey: @"bydaydays"]);
    NSArray *bydayfreq = [recurrence objectForKey: @"bydayfreq"];
    int position = [[recurrence objectForKey: @"bysetpos"] count] ? [[[recurrence objectForKey: @"bysetpos"] objectAtIndex: 0] intValue] : 0;
    NSDate *year = startDate;
    
    if ([bydayfreq count] && [[bydayfreq objectAtIndex: 0] intValue])
      units = NSYearCalendarUnit | NSMonthCalendarUnit | NSWeekdayCalendarUnit | NSWeekdayOrdinalCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
    else
      units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
    
    [advComps setYear: interval];
    
    for (ret = 0 ; ret >= 0 ; ) {
      NSEnumerator *bymonthEnum = [bymonth objectEnumerator];
      id month;

      while ((month = [bymonthEnum nextObject])) {
        int monthValue = [month intValue];
        comps = [cal components: units fromDate: year];

        [comps setMonth: monthValue];

        if ([bydayfreq count] < 2) {
          if ([[bydayfreq objectAtIndex: 0] intValue]) {
            [comps setWeekdayOrdinal: [[bydayfreq objectAtIndex: 0] intValue]];
            [comps setWeekday: [[weekdays objectAtIndex: 0] intValue]];
          }
          
          occurrenceDate = [cal dateFromComponents: comps];
          comps = [cal components: units & ~(NSWeekdayCalendarUnit | NSWeekdayOrdinalCalendarUnit) fromDate: occurrenceDate];
          if ([comps month] != monthValue)
            continue;
        } else {
          NSRange dayRange = [cal rangeOfUnit: NSDayCalendarUnit inUnit: NSMonthCalendarUnit forDate: [cal dateFromComponents: comps]];
          
          [comps setDay: position >= 0 ? 1 : NSMaxRange (dayRange)];
          
          occurrenceDate = [cal dateFromComponents: comps];

          for (int pos = 0 ; pos < abs (position) ; ) {
            comps = [cal components: NSWeekdayCalendarUnit fromDate: occurrenceDate];
            if ([weekdays indexOfObject: [NSNumber numberWithInt: [comps weekday]]] != NSNotFound)
              pos++;
            if (pos < abs (position))
              occurrenceDate = [occurrenceDate addTimeInterval: kSecondsInDay * position/abs(position)];
          }
        }

        ret = checkOccurrence (&foundOccurrence, occurrenceDate, exceptions, until, &count, startDate, after);
      }
      
      year = [cal dateByAddingComponents: advComps toDate: year options: 0];
      if (!bymonth)
        ret = checkOccurrence (&foundOccurrence, year, exceptions, until, &count, startDate, after);
    }
  } else if ([frequency isEqualToString: @"monthly"]) {
    NSArray *bymonthday = [recurrence objectForKey: @"bymonthday"];
    NSArray *weekdays = daysToWeekdays ([recurrence objectForKey: @"bydaydays"]);
    NSArray *bydayfreq   = [recurrence objectForKey: @"bydayfreq"];
    int position = [[recurrence objectForKey: @"bysetpos"] count] ? [[[recurrence objectForKey: @"bysetpos"] objectAtIndex: 0] intValue] : 0;

    NSDate *month = startDate;
    
    [advComps setMonth: interval];

    if ([bymonthday isKindOfClass: [NSArray class]]) {
      units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
      
      for (ret = 0 ; ret >= 0 ; ) {
        int lastDayOfMonth = NSMaxRange ([cal rangeOfUnit: NSDayCalendarUnit inUnit: NSMonthCalendarUnit forDate: month]);
        NSEnumerator *bymonthdayEnum = [bymonthday objectEnumerator];
        id day;
        comps = [cal components: units fromDate: month];
        
        while ((day = [bymonthdayEnum nextObject])) {
          int dayValue = [day intValue];
          if (dayValue > lastDayOfMonth)
            continue;
          
          [comps setDay: dayValue];
          occurrenceDate = [cal dateFromComponents: comps];
          
          ret = checkOccurrence (&foundOccurrence, [cal dateFromComponents: comps], exceptions, until, &count, startDate, after);
        }
        
        month = [cal dateByAddingComponents: advComps toDate: month options: 0];
      }
    } else if (bydayfreq) {
      units = NSYearCalendarUnit | NSMonthCalendarUnit | NSWeekdayCalendarUnit | NSWeekdayOrdinalCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
      
      for (ret = 0 ; ret >= 0 ; ) {
        int lastDayOfMonth = NSMaxRange ([cal rangeOfUnit: NSDayCalendarUnit inUnit: NSMonthCalendarUnit forDate: month]);

        comps = [cal components: units fromDate: month];
        
        if ([weekdays count] == 1) {
          if ([[bydayfreq objectAtIndex: 0] intValue] > 4)
            [comps setWeekdayOrdinal: -1];
          else
            [comps setWeekdayOrdinal: [[bydayfreq objectAtIndex: 0] intValue]];
          [comps setWeekday: [[weekdays objectAtIndex: 0] intValue]];
          
          occurrenceDate = [cal dateFromComponents: comps];
        } else {          
          [comps setDay: position >= 0 ? 1 : lastDayOfMonth];
          occurrenceDate = [cal dateFromComponents: comps];

          for (int pos = 0 ; pos < abs (position) ; ) {
            comps = [cal components: NSWeekdayCalendarUnit fromDate: occurrenceDate];
            if ([weekdays indexOfObject: [NSNumber numberWithInt: [comps weekday]]] != NSNotFound)
              pos++;
            if (pos < abs (position))
              occurrenceDate = [occurrenceDate addTimeInterval: kSecondsInDay * position/abs(position)];
          }
        }
        
        ret = checkOccurrence (&foundOccurrence, occurrenceDate, exceptions, until, &count, startDate, after);

        /* even if the next month does not have the same number of days this will work */
        month = [cal dateByAddingComponents: advComps toDate: month options: 0];
      }
    } else {
      comps = [cal components: NSDayCalendarUnit fromDate: startDate];

      for (i = 1, ret = 0 ; ret >= 0 ; i++) {
        [advComps setMonth: i];
        /* even if the next month does not have the same number of days this will work */
        occurrenceDate = [cal dateByAddingComponents: advComps toDate: startDate options: 0];
        testComps = [cal components: NSDayCalendarUnit fromDate: occurrenceDate];
        
        /* make sure the day exists */
        if ([testComps day] != [comps day])
          continue;

        ret = checkOccurrence (&foundOccurrence, occurrenceDate, exceptions, until, &count, startDate, after);
      }
    }
  } else if ([frequency isEqualToString: @"weekly"]) {
    NSArray *weekdays = daysToWeekdays ([recurrence objectForKey: @"bydaydays"]);
    NSDate *week = startDate;
    
    comps = [cal components: NSWeekdayCalendarUnit fromDate: startDate];
    
    [advComps setWeek: interval];
    
    for (ret = 0 ; ret >= 0 ; ) {
      NSEnumerator *weekdayEnum = [weekdays objectEnumerator];
      id weekday;

      while ((weekday = [weekdayEnum nextObject]))
        ret = checkOccurrence (&foundOccurrence, [week addTimeInterval: ([weekday intValue] - [comps weekday]) * kSecondsInDay], exceptions, until, &count, startDate, after);

      week = [cal dateByAddingComponents: advComps toDate: week options: 0];
      if (!weekdays)
        /* simple weekly occurrence */
        ret = checkOccurrence (&foundOccurrence, week, exceptions, until, &count, startDate, after);
    }
  } else if ([frequency isEqualToString: @"daily"]) {
    occurrenceDate = [startDate addTimeInterval: kSecondsInDay * interval];
    while (checkOccurrence (&foundOccurrence, occurrenceDate, exceptions, until, &count, startDate, after) >= 0)
      occurrenceDate = [occurrenceDate addTimeInterval: kSecondsInDay * interval];
  } /* else unrecognized recurrence frequency. return only the start date */
  
  vxSync_log3(VXSYNC_LOG_INFO, @"returning: %s\n", NS2CH(foundOccurrence));
  
  return foundOccurrence;
}

#if 0
NSArray *splitEvent (NSDictionary *event, NSDictionary *recurrence) {
  NSString *frequency = [recurrence objectForKey: @"frequency"];
  NSArray *occurrences = getOccurrences(event, recurrence, nil, 0);
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDate *startDate = [event objectForKey: @"start date"];
  NSDate *endDate   = [event objectForKey: @"end date"];
  NSTimeInterval difference = [endDate timeIntervalSinceDate: startDate];
  
  if ([[recurrence objectForKey: @"bymonth"] count])
    frequency = @"yearly";
  
  if ([frequency isEqualToString: @"daily"] || [frequency isEqualToString: @"weekly"]) {
    return [NSArray arrayWithObject: event];
  } else if ([frequency isEqualToString: @"monthly"]) {
    if ([[recurrence objectForKey: @"bydayfreq"] count] > 1) {
      for (id occurrence in occurrences) {
        NSMutableDictionary *splitevent = [[event mutableCopy] autorelease];
        NSDateComponents *comp = [cal components: NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate: occurrence];
        NSDate *start = [cal dateByAddingComponents: comp toDate: startDate options: 0];
        NSDate *end   = [start addTimeInterval: difference];
        
        [splitevent removeObjectForKey: @"recurrences"];
        [splitevent setObject: start forKey: @"start date"];
        [splitevent setObject: end forKey: @"end date"];
      }
    } else if ([[recurrence objectForKey: @"bymonthday"] count] > 1) {
      for (id day in [recurrence objectForKey: @"bymonthday"]) {
        NSDateComponents *comp = [[NSDateComponents alloc] init];
        [comp setDay: [day intValue]];
        
        
      }
    }
  } else if ([frequency isEqualToString: @"yearly"]) {
  }
}
#endif

#if defined(__testing_recurrence__)
#warn "recurrence unit test"

int main (int argc, char *argv[]) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys: [[NSDate date] addTimeInterval: 12 * kSecondsInDay], @"start date", [NSArray arrayWithObject: @"dummy"], @"recurrences", nil];
  NSDictionary *recurrence = [NSDictionary dictionaryWithObjectsAndKeys:
					     @"weekly",                    @"frequency",
					     [NSNumber numberWithInt: 1], @"interval",
					   //					     [NSNumber numberWithInt: 5],  @"count",
 					     [NSArray arrayWithObjects: @"monday", @"wednesday", nil], @"bydaydays",
					   [NSArray arrayWithObjects: [NSNumber numberWithInt: 0], [NSNumber numberWithInt: 0], nil], @"bydayfreq",
					   nil];
  NSArray *occurrences = getOccurrences (event, recurrence, [[NSDate date] addTimeInterval: 20 * kSecondsInDay], 1);

  printf ("occurrences = %s\n", [[occurrences description] UTF8String]);

  [releasePool release];

  return 0;
}
#endif
