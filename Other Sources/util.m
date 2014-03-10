/* (-*- objc -*-)
 * vxSync: util.m
 * (C) 2009-2011 Nathan Hjelm
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

#include "util.h"
#include "log.h"
#include "defines.h"

#define kBundleDomain @"com.enansoft.vxSync"

@implementation NSDate (BREW)

+ (id) dateWithTimeIntervalSinceBREWEpochUTC: (int) seconds {
  return [NSDate dateWithTimeIntervalSince1970: seconds + 315964800 - [[NSTimeZone localTimeZone] secondsFromGMT]];
}

+ (id) dateWithTimeIntervalSinceBREWEpochLocal: (int) seconds {
  return [NSDate dateWithTimeIntervalSince1970: seconds + 315964800];
}

+ (id) dateWithLGCalendarDate: (u_int32_t) lgCalDate {
  u_int16_t components[6] = {lgCalDate >> 20, (lgCalDate >> 16) & 0xf, (lgCalDate >> 11) & 0x1f, (lgCalDate >> 6) & 0x1f, lgCalDate & 0x3f, 0};
  return [NSDate dateWithLGDateLocal: components];
}

+ (id) dateWithLGDate: (u_int16_t[6]) dateData timeZone: (NSTimeZone *) timeZone {
  NSDateComponents *comps = [[[NSDateComponents alloc] init] autorelease];
  NSCalendar *UTCCalendar = [NSCalendar currentCalendar];
  
  [UTCCalendar setTimeZone: timeZone];
  
  [comps setYear: dateData[0]];
  [comps setMonth: dateData[1]];
  [comps setDay: dateData[2]];
  [comps setHour: dateData[3]];
  [comps setMinute: dateData[4]];
  [comps setSecond: dateData[5]];
  
  return [UTCCalendar dateFromComponents: comps];
}

+ (id) dateWithLGDateLocal: (u_int16_t[6]) dateData {
  return [NSDate dateWithLGDate: dateData timeZone: [NSTimeZone localTimeZone]];
}

+ (id) dateWithLGDateUTC: (u_int16_t[6]) dateData {
  return [NSDate dateWithLGDate: dateData timeZone: [NSTimeZone timeZoneWithName: @"UTC"]];
}

- (u_int32_t) timeIntervalSinceBREWEpochUTC {
  return [self timeIntervalSince1970] - 315964800 + [[NSTimeZone localTimeZone] secondsFromGMT];
}

- (u_int32_t) timeIntervalSinceBREWEpochLocal {
  return [self timeIntervalSince1970] - 315964800;
}

- (u_int32_t) LGCalendarDate {
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *comps = [cal components: (NSYearCalendarUnit | NSMonthCalendarUnit |  NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit) fromDate: self];
  
  if ([comps year] > 4095)
    [comps setYear: 4095];
  
  return ([comps year] << 20) | ([comps month] << 16) | ([comps day] << 11) | ([comps hour] << 6) | [comps minute];
}

- (void) lgDate: (u_int16_t[6]) dateData {
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *comps = [cal components: (NSYearCalendarUnit | NSMonthCalendarUnit |  NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit) fromDate: self];
  
  dateData[0] = [comps year];
  dateData[1] = [comps month];
  dateData[2] = [comps day];
  dateData[3] = [comps hour];
  dateData[4] = [comps minute];
  dateData[5] = [comps second];
}

@end

NSCalendarDate *calendarDateFromLGCalendarDate (u_int32_t LGCalDate) {
  return [[NSDate dateWithLGCalendarDate: LGCalDate] dateWithCalendarFormat: nil timeZone: nil];
}

/* remove formatting characters from phone number */
NSString *unformatNumber (NSString *input) {
  return [[[input uppercaseString] componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789#*+PW"] invertedSet]] componentsJoinedByString:@""];
#if 0
  NSMutableString *strippedString = [NSMutableString string];
  int i;
  
  for (i = 0; i < [input length]; i++) {
    char digit = [input characterAtIndex:i];
    if (isdigit(digit) || '#' == digit || '*' == digit || '+' == digit || 'P' == digit || 'W' == digit) {
      [strippedString appendFormat:@"%c", digit];
    }
  }
  
  return [[strippedString copy] autorelease];
#endif
}

NSString *formattedNumber (const char *input) {
  NSMutableString *fNumber = [NSMutableString stringWithCString: input encoding: NSASCIIStringEncoding];
  size_t length = [fNumber length];
  
  if ([fNumber rangeOfCharacterFromSet: [NSCharacterSet characterSetWithCharactersInString:@"#*+PW"]].location == NSNotFound) {
    switch (length) {
      case 11:
        [fNumber insertString: @"-" atIndex: 1]; /* x-xxxxxxxxxx   */
        [fNumber insertString: @"-" atIndex: 5]; /* x-xxx-xxxxxxx  */
        [fNumber insertString: @"-" atIndex: 9]; /* x-xxx-xxx-xxxx */
        break;
      case 10:
        [fNumber insertString: @"-" atIndex: 3]; /* xxx-xxxxxxx  */
        [fNumber insertString: @"-" atIndex: 7]; /* xxx-xxx-xxxx */
        break;
      case 7:
        [fNumber insertString: @"-" atIndex: 3]; /* xxx-xxxx */
      default:
        break;
    }
  }
  return [[fNumber copy] autorelease];
}

void splitName (NSString *fullName, NSMutableDictionary *store) {
  NSPredicate *noEmptyPredicate = [NSPredicate predicateWithFormat: @"SELF != %@", @""];
  NSArray *names1 = [[fullName componentsSeparatedByString: @","] filteredArrayUsingPredicate: noEmptyPredicate];
  NSArray *names2 = [[fullName componentsSeparatedByString: @" "] filteredArrayUsingPredicate: noEmptyPredicate];

  [store setObject: fullName forKey: VXKeyFullName];
  if ([names1 count] > 1) {
    NSMutableArray *firstName = [NSMutableArray array];
    
    [store setObject: [names1 objectAtIndex: 0] forKey: @"last name"];
    for (id name in [names1 subarrayWithRange: NSMakeRange(1, [names1 count] - 1)]) {
      NSString *fixedName = [[[name componentsSeparatedByString: @" "] filteredArrayUsingPredicate: noEmptyPredicate] componentsJoinedByString: @" "];
      [firstName addObject: fixedName];
    }
    [store setObject: [firstName componentsJoinedByString: @", "] forKey: @"first name"];
  } else if ([names2 count] > 1) {
    [store setObject: [names2 objectAtIndex: 0] forKey: @"first name"];
    [store setObject: [[names2 subarrayWithRange: NSMakeRange (1, [names2 count] - 1)] componentsJoinedByString: @" "] forKey: @"last name"];
  } else
    [store setObject: fullName forKey: @"first name"];
}

NSString *shortenString (NSString *theString, NSStringEncoding theEncoding, int maxLength) {
  NSData *stringData = [theString dataUsingEncoding: theEncoding allowLossyConversion: YES];

  if (!theString)
    return nil;
  
  vxSync_log3(VXSYNC_LOG_INFO, @"shortening string %s to a max length of %d\n", theString, maxLength);
  
  if ([stringData length] >= maxLength)
    stringData = [stringData subdataWithRange: NSMakeRange(0, maxLength-1)];
  
  return [[[NSString alloc] initWithData: stringData encoding: theEncoding] autorelease];
}

NSBundle *vxSyncBundle (void) {
  NSBundle *bundle;

  bundle = [NSBundle bundleWithIdentifier: kBundleDomain];
  
  if (!bundle) {
    bundle = [NSBundle mainBundle];
    if ([[bundle bundlePath] hasSuffix: @"Resources"])
      bundle = [NSBundle bundleWithPath: [[bundle bundlePath] stringByReplacingOccurrencesOfString: @"/Contents/Resources" withString: @""]];
  }

  return bundle;
}

NSString *stringFromBuffer (const unsigned char *buffer, int maxLength, u_int64_t encoding) {
  if ((unsigned int)NSISOLatin1StringEncoding == encoding || (unsigned int)NSASCIIStringEncoding == encoding || (unsigned int)NSUTF8StringEncoding == encoding)
    return [NSString stringWithCString: (char *)buffer encoding: encoding];
  if ((unsigned int)NSUTF16StringEncoding == encoding || (unsigned int)NSUTF16LittleEndianStringEncoding == encoding || (unsigned int)NSUTF16BigEndianStringEncoding == encoding) {
    u_int16_t *char16 = (u_int16_t *)buffer;
    int i;
      
    for (i = 0 ; i < maxLength/2 ; i++)
      if (char16[i] == 0)
        break;
    
    return [[[NSString alloc] initWithBytes: buffer length: i*2 encoding: encoding] autorelease];
  }

  return nil;
}

NSString *flattenHTML (NSString *htmlString) {
  NSError *theError = NULL;
  NSXMLDocument *theDocument = [[[NSXMLDocument alloc] initWithXMLString: htmlString options:NSXMLDocumentTidyHTML error: &theError] autorelease];
  NSString *theXSLTString = @"<?xml version='1.0' encoding='utf-8'?>\n<xsl:stylesheet version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform' xmlns:xhtml='http://www.w3.org/1999/xhtml'>\n<xsl:output method='text' encoding='iso-8859-1'/><xsl:template match='xhtml:head'></xsl:template><xsl:template match='xhtml:script'></xsl:template></xsl:stylesheet>";
  NSData *theData = [theDocument objectByApplyingXSLTString: theXSLTString arguments: NULL error: &theError];
  if ([theData respondsToSelector: @selector(length)])
    return [[[NSString alloc] initWithData: theData encoding: NSISOLatin1StringEncoding] autorelease];
  /* unable to parse HTML (happens when the rendered data is blank) */
  return @"";
}

NSInteger sortAscending (id ob1, id ob2, void *context) {
  return [[ob1 objectForKey: context] compare: [ob2 objectForKey: context]];
}

NSInteger sortDescending (id ob1, id ob2, void *context) {
  return [[ob2 objectForKey: context] compare: [ob1 objectForKey: context]];
}

id extractValue (id arg, void *context) {
  return [(NSDictionary *)arg objectForKey: (NSString *)context];
}

void unpackValue (u_int8_t **ptrp, void *stp, int size) {
  u_int8_t  *st8  = (u_int8_t *)stp;
  u_int16_t *st16 = (u_int16_t *)stp;
  u_int32_t *st32 = (u_int32_t *)stp;
  u_int64_t *st64 = (u_int64_t *)stp;
  
  if (stp) {
    if (size == 2)
      *st16 = OSReadLittleInt16 (*ptrp, 0);
    else if (size == 4)
      *st32 = OSReadLittleInt32 (*ptrp, 0);
    else if (size == 8)
      *st64 = OSReadLittleInt64 (*ptrp, 0);
    else if (size == 1)
      *st8 = (*ptrp)[0];
  }
  
  (*ptrp) += size; 
}

void unpackString (u_int8_t **ptrp, char *stp, int length) {
  if (stp)
    memcpy (stp, *ptrp, length);
  
  *ptrp += length;
}

void packValue (u_int8_t **ptrp, unsigned int ld, int size) {
  switch (size) {
    case 1:
      (*ptrp)[0] = (u_int8_t)ld;
      break;
    case 2:
      OSWriteLittleInt16 (*ptrp, 0, (u_int16_t)ld);
      break;
    case 4:
      OSWriteLittleInt32 (*ptrp, 0, (u_int32_t)ld);
      break;
    case 8:
      OSWriteLittleInt64 (*ptrp, 0, (u_int64_t)ld);
      break;
  }
  
  (*ptrp) += size;
}

void packString (u_int8_t **ptrp, char *ldp, int len) {
  if (len == -1)
    len = strlen (ldp) + 1;
  
  memmove ((char *)*ptrp, ldp, len);
  *ptrp += len;
}

void pretty_print_block (unsigned char *b, int len){
  int x, y, indent, count = 0;
  
  indent = 32; /* whatever */
  
  fputc('\n', stderr);
  
  while (count < len){
    fprintf(stderr, "%04x : ", count);
    for (x = 0 ; x < indent ; x++){
	    fprintf(stderr, "%02x ", b[x + count]);
	    if ((x + count + 1) >= len){
        x++;
        for (y = 0 ; y < (indent - x) ; y++)
          fprintf(stderr, "   ");
        break;
	    }
    }
    fprintf(stderr, ": ");
    
    for (x = 0 ; x < indent ; x++){
	    if (isprint(b[x + count]))
        fputc(b[x + count], stderr);
	    else
        fputc('.', stderr);
	    
	    if ((x + count + 1) >= len){
        x++;
        for (y = 0 ; y < (indent - x) ; y++)
          fputc(' ', stderr);
        break;
	    }
    }
    
    fputc('\n', stderr);
    count += indent;
  }
  
  fputc('\n', stderr);
}

int ppp_escape_inplace (u_int8_t *msg, size_t len, size_t buffer_len) {
  u_int8_t tmp[8192];
  int i, j;
  
  buffer_len = buffer_len > 8192 ? 8192 : buffer_len;
  
  for (i = 0, j = 0 ; j < len && i < buffer_len ; j++) {
    switch (msg[j]) {
      case 0x7d:
      case 0x7e:
        tmp[i++] = 0x7d;
        tmp[i++] = msg[j] ^ 0x20;
        break;
      default:
        tmp[i++] = msg[j];
    }
  }
  
  if (i == buffer_len) {
    errno = ENOBUFS;
    return -1;
  }
  
  /* terminator */
  tmp[i++] = 0x7e;
  memmove (msg, tmp, i);
  
  return i;
}

int ppp_unescape_inplace(u_int8_t *msg, size_t len) {
  int i, j;
  
  for (i = 0, j = 0 ; j < len ; j++, i++) {
    if (msg[j] == 0x7d && j < len - 1)
      msg[i] = msg[++j] ^ 0x20;
    else if (msg[j] == 0x7e) {
      msg[i] = '\0';
      break;
    } else if (i != j)
      msg[i] = msg[j];
  }
  
  return i;
}

@implementation NSDictionary (vxSync)
- (NSSet *) keysOfObjectsPassingTest: (BOOL (*)(id key, id obj, BOOL *stop)) predicate {
  NSMutableSet *keys = [NSMutableSet set];
  BOOL stop = NO;
  
  for (id key in self) {
    if (predicate (key, [self objectForKey: key], &stop))
      [keys addObject: key];
    if (stop)
      break;
  }
  
  return [[keys copy] autorelease];
}
@end

@implementation NSArray (map)
- (id) mapSelector: (SEL) aSelector withObject: (id) anObject {
  NSMutableArray *newArray = [NSMutableArray arrayWithCapacity: [self count]];

  for (id obj in self)
    [newArray addObject: [obj performSelector: aSelector withObject: anObject]];

  return newArray;
}

- (id) mapSelector: (SEL) aSelector {
  NSMutableArray *newArray = [NSMutableArray arrayWithCapacity: [self count]];

  for (id obj in self)
    [newArray addObject: [obj performSelector: aSelector]];

  return newArray;
}
@end

@implementation NSString (counter)
- (unsigned int) countOccurencesOfSubstring: (NSString *) subString {
  unsigned int count;
  NSUInteger start = 0;
  unsigned int totalLength = [self length];
  NSRange searchRange;

  for (count = 0 ; NSNotFound != start ; count++) {
    searchRange = NSMakeRange(start, totalLength - start);
    start = NSMaxRange([self rangeOfString: subString options: 0 range: searchRange]);
  }
  
  return count;
}
@end

#if defined(UTIL_UNIT_TEST)
int main (void) {
  NSAutoreleasePool *releasePool = [[NSAutoreleasePool alloc] init];
  NSString *formattedString = @"111-1111";
  NSString *unformattedString = unformatNumber(formattedString);
  
  printf ("formatted  : %s\n", [formattedString UTF8String]);
  printf ("unformatted: %s\n", [unformattedString UTF8String]);
  printf ("reformatted: %s\n", [formattedNumber([unformattedString cStringUsingEncoding: NSASCIIStringEncoding]) UTF8String]);

  [releasePool release];
  
  return 0;
}
#endif