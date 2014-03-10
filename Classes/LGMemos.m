/* (-*- objc -*-)
 * vxSync: LGMemos.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.8.5
 *
 * Changes:
 *  - 0.2.0 - initial release.
 *  - 0.2.3 - bug fixes.
 *  - 0.3.0 - bug fixes.
 *  - 0.3.1 - code cleanup
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

#include <stdlib.h>
#include <stdio.h>

#include "LGMemos.h"

@interface LGMemos (hidden)
- (int) modifyInternalRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew;
- (int) refreshInternalData;
@end

@implementation LGMemos

@synthesize phone, delegate, internalRecords;

const static size_t mDateOffset[2] = { 305, 308 };
const static size_t memoLength[2]  = { 301, 304 };
const size_t memoSize = 312; /* both supported formats */

+ (id) sourceWithPhone: (vxPhone *) phoneIn {
  return [[[LGMemos alloc] initWithPhone: phoneIn] autorelease];
}

- (NSString *) dataSourceIdentifier {
  return @"com.enansoft.memos";
}

- (NSArray *) supportedEntities {
  return [NSArray arrayWithObject: @"com.apple.notes.Note"];
}

- (id) initWithPhone: (vxPhone *) phoneIn {
  self = [super init];
  if (!self)
    return nil;

  [self setPhone: phoneIn];

  memoLimit  = [phone limitForEntity: EntityNote];
  memoFormat = [phone formatForEntity: EntityNote];

  return self;
}

- (void) dealloc {
  [self setPhone: nil];
  [self setDelegate: nil];

  [self setInternalRecords: nil];
  
  [super dealloc];
}

- (int) refreshInternalData {
  int i, offset, memoCount;
  NSData *fileData;
  NSString *error = nil;
  const unsigned char *bytes;
  
  printf ("Reading notes...\n");

  [self setInternalRecords: [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableDictionary dictionary], EntityNote, nil]];
  
  fileData = [[phone efs] get_file_data_from: VXMemoPath errorOut: &error];
  bytes = [fileData bytes];

  if (error) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"could not read memo data: %s\n", NS2CH(error));
    memoCount = 0;
    return 0;
  }
  
  memoCount = ![fileData length] ? 0 : OSReadLittleInt32 (bytes, 0);

  vxSync_log3(VXSYNC_LOG_DEBUG, @"memo count: %d\n", memoCount);
  
  for (i = 0, offset = 4 ; i < memoCount ; i++, offset += memoSize) {
    NSString *content =  stringFromBuffer(bytes + offset + 4, memoLength[memoFormat], NSISOLatin1StringEncoding);
    NSMutableDictionary *newNote = [NSMutableDictionary dictionaryWithCapacity: 8];
    id oldRecord;

    [newNote setObject: EntityNote forKey: RecordEntityName];
    [newNote setObject: content forKey: @"content"];
    [newNote setObject: [[content componentsSeparatedByString: @"\n"] objectAtIndex: 0] forKey: @"subject"];
    [newNote setObject: @"text/plain" forKey: @"contentType"];
    [newNote setObject: [NSDate dateWithTimeIntervalSinceBREWEpochLocal: OSReadLittleInt32 (bytes + offset, 0)] forKey: @"dateCreated"];
    [newNote setObject: [NSDate dateWithLGCalendarDate: OSReadLittleInt32 (bytes + offset + mDateOffset[memoFormat], 0)] forKey: @"dateModified"];
    
    /* ask the delegate what the identifier should be for this record -- dateCreated is sufficient */
    [delegate getIdentifierForRecord: newNote compareKeys: [NSArray arrayWithObjects: @"dateCreated", nil]];
    
    oldRecord = [delegate findRecordWithIdentifier: [newNote objectForKey: VXKeyIdentifier] entityName: EntityNote];
    [newNote setObject: oldRecord ? [oldRecord objectForKey: @"author"] : @"Unknown" forKey: @"author"];
    
    if ([[internalRecords objectForKey: EntityNote] objectForKey: [newNote objectForKey: VXKeyIdentifier]])
      vxSync_log3(VXSYNC_LOG_WARNING, @"note id collision. the following notes have the same identifier: %s, %s\n", NS2CH(newNote), NS2CH([[internalRecords objectForKey: EntityNote] objectForKey: [newNote objectForKey: VXKeyIdentifier]]));
    
    [[internalRecords objectForKey: EntityNote] setObject: newNote forKey: [newNote objectForKey: VXKeyIdentifier]];
  }
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"internalRecords = %s\n", NS2CH(internalRecords));
  
  return 0;
}

- (NSDictionary *) readRecords {  
  if (!internalRecords && [self refreshInternalData] < 0)
    return nil;

  return [[internalRecords copy] autorelease];
}

- (int) deleteRecord: (NSDictionary *) record {
  [[internalRecords objectForKey: EntityNote] removeObjectForKey: [record objectForKey: VXKeyIdentifier]];

  return 0;
}

- (NSDictionary *) formatRecord: (NSDictionary *) record identifier: (NSString *) identifier {
  NSString *content = [record objectForKey: @"content"];
  NSMutableDictionary *formattedRecord = [[record mutableCopy] autorelease];
  
  vxSync_log3(VXSYNC_LOG_DEBUG, @"formatting note: %s\n", NS2CH(record));
  
  /* no supported phones use html for notes afaik */
  /* some notes come in with html formatting get have contentType == text/plain */
  if ([[record objectForKey: @"contentType"] isEqualToString: @"text/html"] || [content hasPrefix: @"<html>"])
    content = flattenHTML (content);
  
  /* shorted the content to fit in the memo */
  if ([content length] >= memoLength[memoFormat])
    content = shortenString (content, NSISOLatin1StringEncoding, memoLength[memoFormat]);
  
  [formattedRecord setObject: content forKey: @"content"];
  [formattedRecord setObject: @"text/plain" forKey: @"contentType"];

  [formattedRecord setObject: [[[formattedRecord objectForKey: @"content"] componentsSeparatedByString: @"\n"] objectAtIndex: 0] forKey: @"subject"];

  /* no more changes need to be sent to the sync engine */
  return [[formattedRecord copy] autorelease];
}

- (int) addRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  return [self modifyInternalRecord: record formattedRecordOut: recordOut identifier: identifier isNew: YES];
}

- (int) modifyRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier {
  return [self modifyInternalRecord: record formattedRecordOut: recordOut identifier: identifier isNew: NO];
}

- (int) modifyInternalRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier isNew: (BOOL) isNew {
  NSDictionary *internalRecord = [[internalRecords objectForKey: EntityNote] objectForKey: identifier];
  NSMutableDictionary *formattedRecord;
  
  if (!isNew && !internalRecord) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"could find a record matching modified record: %s\n", NS2CH(record));
    return -2;
  } else if (isNew && internalRecord)
    vxSync_log3(VXSYNC_LOG_WARNING, @"\"new\" record matches an old record\n");
  
  if (isNew && [[internalRecords objectForKey: EntityNote] count] >= memoLimit) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"no space available to store record: %s\n", NS2CH(record));
    return -2;
  }
  
  formattedRecord = [[record mutableCopy] autorelease];
  [formattedRecord setObject: identifier forKey: VXKeyIdentifier];
  
  *recordOut = [[formattedRecord copy] autorelease];
  
  [[internalRecords objectForKey: EntityNote] setObject: formattedRecord forKey: identifier];
  
  return 0;
}

- (BOOL) deleteAllRecordsForEntityName: (NSString *) entityName {
  if (![entityName isEqual: EntityNote])
    return NO;

  [self setInternalRecords: [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSMutableDictionary dictionary], EntityNote, nil]];
  return YES;
}

- (BOOL) deleteAllRecords {
  return [self deleteAllRecordsForEntityName: EntityNote];
}

- (int) commitChanges {
  int i, memoCount;
  NSMutableData *memoData;
  unsigned char *bytes;
  NSArray *keys;

  if (!internalRecords)
    return 0; /* nothing to do */

  keys = [[internalRecords objectForKey: EntityNote] allKeys];
  memoCount = [keys count];
  memoData = [NSMutableData dataWithLength: memoCount * memoSize + 4];
  bytes    = [memoData mutableBytes];
  OSWriteLittleInt32 (bytes, 0, memoCount);

  vxSync_log3(VXSYNC_LOG_INFO, @"commiting memo changes to phone\n");
  for (i = 0 ; i < memoCount ; i++) {
    size_t offset = 4 + i * memoSize;
    NSDictionary *record = [[internalRecords objectForKey: EntityNote] objectForKey: [keys objectAtIndex: i]];

    OSWriteLittleInt32 (bytes + offset, 0, [[record objectForKey: @"dateCreated"] timeIntervalSinceBREWEpochLocal]);
    OSWriteLittleInt32 (bytes + offset + mDateOffset[memoFormat], 0, [[record objectForKey: @"dateModified"] LGCalendarDate]);

    [[record objectForKey: @"content"] getCString: (char *)(bytes + offset + 4) maxLength: memoLength[memoFormat] encoding: NSISOLatin1StringEncoding];
  }

  return ([[phone efs] write_file_data: memoData to: VXMemoPath] >= 0) ? 0 : -1;
}

@end
