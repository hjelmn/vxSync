/* (-*- objc -*-)
 * vxSync: LGExceptions.m
 * (C) 2009-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "LGExceptions.h"

@interface LGExceptions (hidden)
- (int) refreshInternalData;
@end

@implementation LGExceptions

+ (id) exceptionsWithPhone: (vxPhone *) phoneIn {
  return [[[LGExceptions alloc] initWithPhone: phoneIn] autorelease];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];
  if (!self || !phoneIn)
    return nil;
  
  [self setPhone: phoneIn];
  [self refreshInternalData];
  
  return self;
}

@synthesize phone, internalData;

- (void) dealloc {
  [self setPhone: nil];
  [self setInternalData: nil];

  [super dealloc];
}

- (int) refreshInternalData {
  int ret, fd = -1;
  struct stat statinfo;
  
  @try {
    ret = [[phone efs] stat: VXExceptionPath to: &statinfo];
    if (ret != 0)
      @throw [NSException exceptionWithName: @"could not stat exceptions file" reason: [NSString stringWithUTF8String: strerror (errno)] userInfo: nil];
    
    bytesLength = statinfo.st_size;
    
    [self setInternalData: [NSMutableData dataWithLength: bytesLength]];
    bytes = [internalData mutableBytes];
    fd = [[phone efs] open: VXExceptionPath withFlags: O_RDONLY];
    if (-1 == fd)
      @throw [NSException exceptionWithName: @"could not open exceptions for reading" reason: [NSString stringWithUTF8String: strerror (errno)] userInfo: nil];
    
    bytesLength = [[phone efs] read: fd to: bytes count: bytesLength];
    [[phone efs] close: fd];
    if (bytesLength < 0)
      @throw [NSException exceptionWithName: @"error reading exceptions" reason: [NSString stringWithUTF8String: strerror (errno)] userInfo: nil];
    
    exceptionCount = bytesLength / sizeof (struct lg_schedule_exception);
  } @catch (NSException *e) {
    vxSync_log3(VXSYNC_LOG_ERROR, @"could not allocate internal buffer of length %d: reason = %s\n", statinfo.st_size, NS2CH([e reason]));
    ret = -1;
  } @finally {
    [[phone efs] close: fd];
    
    ret = 0;
  }
  
  return ret;
}

- (NSArray *) exceptionsForEvent: (u_int16_t) eventID startTime: (u_int32_t) startTime {
  NSMutableArray *exceptions = [NSMutableArray array];
  int i;
  
  for (i = 0 ; i < exceptionCount ; i++) {
    struct lg_schedule_exception *exception = (struct lg_schedule_exception *) (bytes + i * sizeof (struct lg_schedule_exception));
    if (OSSwapLittleToHostInt16 (exception->offset) == eventID)
      [exceptions addObject: [NSCalendarDate dateWithYear: OSSwapLittleToHostInt16 (exception->year)
                                                    month: exception->month
                                                      day: exception->day
                                                     hour: (startTime >> 6) & 0x1f 
                                                   minute: startTime & 0x3f
                                                   second: 0
                                                 timeZone: [NSTimeZone localTimeZone]]];
  }
  
  return [[exceptions copy] autorelease];
}

- (void) removeAllExceptions {
  vxSync_log3(VXSYNC_LOG_INFO, @"removing all exceptions\n");
  [self setInternalData: [NSMutableData dataWithLength: 10]];
  exceptionCount = 0;
  bytes = [internalData mutableBytes];
}

- (void) removeExeptionsForEvent: (u_int16_t) eventID {
  int i;
  
  /* braindead traverse and remove (should be plenty fast with only 300 calendar entries) */
  for (i = 0 ; i < exceptionCount ; ) {
    struct lg_schedule_exception *exception = (struct lg_schedule_exception *)(bytes + i * sizeof (struct lg_schedule_exception));
    if (OSSwapLittleToHostInt16 (exception->offset) == eventID) {
      memmove (bytes + i * sizeof (struct lg_schedule_exception),  bytes + (i + 1) * sizeof (struct lg_schedule_exception), sizeof (struct lg_schedule_exception));
      exceptionCount--;
    } else
      i++;
  }
}

- (void) addExceptionsFromArray: (NSArray *) exceptions eventID: (u_int16_t) eventID {
  int i, newExceptionCount = exceptionCount + [exceptions count];
  
  if ([internalData length] < sizeof (struct lg_schedule_exception) * newExceptionCount) {
    @try {
      [internalData increaseLengthBy: sizeof (struct lg_schedule_exception) * 4 * [exceptions count]];
    }
    @catch (NSException *e) {
      NSLog (@"vxSync/LGCalendar/Exceptions -addExceptionsFromArray:eventID: could not increase internal buffer length: reason = %s\n", NS2CH([e reason]));
      return;
    }
    
    bytes = [internalData mutableBytes];
  }
  
  for (i = exceptionCount ; i < newExceptionCount ; i++) {
    struct lg_schedule_exception exception;
    NSCalendarDate *exceptionDate = [exceptions objectAtIndex: i - exceptionCount];
    exception.offset = OSSwapLittleToHostInt16 (eventID);
    exception.year   = OSSwapLittleToHostInt16 ([exceptionDate yearOfCommonEra]);
    exception.month  = [exceptionDate monthOfYear];
    exception.day    = [exceptionDate dayOfMonth];
    memmove (bytes + i * sizeof (struct lg_schedule_exception), &exception, sizeof(struct lg_schedule_exception));
  }
  
  exceptionCount = newExceptionCount;
}

- (int) commitChanges {
  int fd;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"commiting exception changes...\n");

  fd = [[phone efs] open: VXExceptionPath withFlags: O_WRONLY | O_TRUNC];
  if (-1 == fd)
    return -1;

  [[phone efs] write: fd from: bytes count: exceptionCount * sizeof(struct lg_schedule_exception)];
  [[phone efs] close: fd];
  return 0;
}
@end
