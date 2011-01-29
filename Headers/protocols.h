/* (-*- objc -*-)
 * vxSync: protocols.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(PROTOCOLS_H)
#define PROTOCOLS_H

#include "VXSync.h"

@class vxPhone;

@protocol PhoneDevice <NSObject>

@property (retain) id location;

+ (NSSet *) scanDevices;
+ (void) startNotifications;
+ (void) stopNotifications;
+ (id) phoneWithLocation: (id) locationIn;
- (id) initWithLocation: (id) locationIn;
- (void) dealloc;
- (int) open;
- (int) close;
- (int) read: (void *) bytes size: (UInt32) count;
- (int) write: (void *) bytes size: (UInt32) count;
- (int) write_message: (u_int8_t *) buffer withLength: (size_t) len bufferSize: (size_t) bufferLen;
- (int) read_message: (u_int8_t *) buffer length: (size_t) len;
@end

@protocol EFS <NSObject>
- (void) dealloc;
- (int) reboot;

@property (readwrite) BOOL requiresReboot;

- (void) doneWithDevice;
- (int) send_recv_message: (unsigned char *) sbuffer sendLength: (size_t) sbuffer_len sendBufferSize: (size_t) sbuffer_size
                   recvTo: (unsigned char *) rbuffer recvLength: (size_t) rbuffer_len;

- (NSData *) get_file_data_from: (NSString *) filename errorOut: (NSString **) error;
/* overwrite/create a file with data */
- (int) write_file_data: (NSData *) data to: (NSString *) filename;

- (int) stat:(NSString *)filename to:(struct stat *)sb;

- (int) open:(NSString *)filename withFlags:(int)oflag, ...;
- (int) close:(int)fd;
- (ssize_t) read:(int)fd to:(unsigned char *)buf count:(size_t)len;
- (ssize_t) write:(int)fd from:(unsigned char *)buf count:(size_t)len;
- (off_t) lseek:(int)fd toOffset:(off_t)offset whence:(int)whence;

- (int) mkdir:(NSString *)filename withMode:(mode_t)mode;
- (DIR *)opendir:(NSString *)filename;
- (int) closedir:(DIR *)dirp;
- (struct dirent *) readdir:(DIR *)dirp;
- (long) telldir:(DIR *)dirp;

- (int) unlink:(NSString *)path;

- (int) chmod:(NSString *)path withMode:(mode_t)mode;
@end

@protocol LGDataDelegate <NSObject>
- (void) getIdentifierForRecord: (NSMutableDictionary *) anObject compareKeys: (NSArray *) keys;
- (id) findRecordWithIdentifier: (NSString *) identifier entityName: (NSString *) entityName;
- (void) modifyRecord: (NSDictionary *) record withIdentifier: (NSString *) identifier withEntityName: (NSString *) entityName;

- (ISyncSessionDriver *) sessionDriver;
@end

@protocol LGData <NSObject>
+ (id) sourceWithPhone: (vxPhone *) phoneIn;
- (id) initWithPhone: (vxPhone *) phoneIn;

- (void) setDelegate: (id) delegate;

- (NSString *) dataSourceIdentifier;
- (NSArray *) supportedEntities;

- (void) dealloc;

/* returns a dictionary whose keys are entity names and whose values are dictionaries whose keys are identifiers and values are records */
- (NSDictionary *) readRecords;

- (NSDictionary *) formatRecord: (NSDictionary *) record identifier: (NSString *) identifier;

/* these methods write data to the phone */
- (int) deleteRecord: (NSDictionary *) record;
- (BOOL) deleteAllRecordsForEntityName: (NSString *) entityName;
- (BOOL) deleteAllRecords;

- (int) modifyRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier;
- (int) addRecord: (NSDictionary *) record formattedRecordOut: (NSDictionary **) recordOut identifier: (NSString *) identifier;

- (int) commitChanges;

@end


#endif
