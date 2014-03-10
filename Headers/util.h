/* (-*- objc -*-)
 * vxSync: util.h
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

#if !defined(UTIL_H)
#define UTIL_H

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>

#include <Cocoa/Cocoa.h>

NSDate *startOfDate (NSDate *date);
NSCalendarDate *calendarDateFromLGCalendarDate (u_int32_t LGCalDate);

NSString *formattedNumber (const char *input);
NSString *unformatNumber (NSString *input);

NSString *shortenString (NSString *theString, NSStringEncoding theEncoding, int maxLength);
NSString *stringFromBuffer (const unsigned char *buffer, int maxLength, u_int64_t encoding);

NSString *flattenHTML (NSString *htmlString);
void splitName (NSString *fullName, NSMutableDictionary *store);

NSInteger sortAscending (id ob1, id ob2, void *context);
NSInteger sortDescending (id ob1, id ob2, void *context);
id extractValue (id arg, void *context);

void unpackValue (u_int8_t **ptrp, void *stp, int size);
void unpackString (u_int8_t **ptrp, char *stpm, int length);
void packValue (u_int8_t **ptrp, unsigned int ld, int size);
void packString (u_int8_t **ptrp, char *ldp, int len);
        
void pretty_print_block (unsigned char *b, int len);

NSBundle *vxSyncBundle (void);

NSDate *getAnOccurrence (NSDictionary *event, NSDictionary *recurrence, NSDate *after);

int ppp_escape_inplace (u_int8_t *msg, size_t len, size_t buffer_len);
int ppp_unescape_inplace(u_int8_t *msg, size_t len);

@interface NSDate (BREW)
+ (id) dateWithTimeIntervalSinceBREWEpochUTC: (int) seconds;
+ (id) dateWithTimeIntervalSinceBREWEpochLocal: (int) seconds;
+ (id) dateWithLGCalendarDate: (u_int32_t) lgCalDate;
+ (id) dateWithLGDate: (u_int16_t[6]) dateData timeZone: (NSTimeZone *) timeZone;
+ (id) dateWithLGDateLocal: (u_int16_t[6]) dateData;
+ (id) dateWithLGDateUTC: (u_int16_t[6]) dateData;

- (u_int32_t) timeIntervalSinceBREWEpochUTC;
- (u_int32_t) timeIntervalSinceBREWEpochLocal;
- (u_int32_t) LGCalendarDate;
- (void) lgDate: (u_int16_t[6]) dateData;
@end

@interface NSArray (map)
- (id) mapSelector: (SEL) aSelector withObject: (id) anObject;
- (id) mapSelector: (SEL) aSelector;
@end

@interface NSDictionary (vxSync)
- (NSSet *) keysOfObjectsPassingTest: (BOOL (*)(id key, id obj, BOOL *stop)) predicate;
@end

@interface NSString (counter)
- (unsigned int) countOccurencesOfSubstring: (NSString *) subString;
@end

#endif
