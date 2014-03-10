/* (-*- objc -*-)
 * vxSync: log.h
 * Copyright (C) 2009-2011 Nathan Hjelm
 * v0.8.2
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

#if !defined(LOG_H)
#define LOG_H

#include <Cocoa/Cocoa.h>

#define vxSync_log3(l,f,args...) [[vxSyncLogger defaultLogger] addMessageWithLevel: (l) func: __func__ line: __LINE__ format: (f), ##args]
#define vxSync_log3_data(l,d,f,args...) [[vxSyncLogger defaultLogger] addMessageWithLevel: (l) func: __func__ line: __LINE__ data: (d) format: (f), ##args]

enum vxSync_log_levels { VXSYNC_LOG_ERROR, VXSYNC_LOG_WARNING, VXSYNC_LOG_INFO, VXSYNC_LOG_DEBUG, VXSYNC_LOG_DATA, VXSYNC_LOG_LAST };

@interface vxSyncLogger : NSObject {
@private
  NSString *prog;
  unsigned int logLevel;
  FILE *filehandle;
  NSArrayController *controller;
  NSMutableArray *lineCounts;
  NSMutableArray *logData;
  NSLock *lock;
}

@property (retain) NSArrayController *controller;
@property (retain) NSString *prog;

@property (assign) unsigned int logLevel;
@property (assign) FILE *filehandle;

@property (retain) NSMutableArray *lineCounts;
@property (retain) NSMutableArray *logData;
@property (retain) NSLock *lock;

+ (vxSyncLogger *) defaultLogger;
+ (void) setDefaultLogger: (vxSyncLogger *) logger;


+ (id) loggerWithLevel: (unsigned int) _level logFd: (int) _fd progName: (NSString *) _prog;
+ (id) loggerWithLevel: (unsigned int) _level controller: (NSArrayController *) _controller progName: (NSString *) _prog;

- (id) initLogWithLevel: (unsigned int) _level logFd: (int) _fd progName: (NSString *) _prog;
- (id) initLogWithLevel: (unsigned int) _level controller: (NSArrayController *) _controller progName: (NSString *) _prog;

- (void) addMessageWithLevel: (int) level func: (const char *) func line: (int) line format: (NSString *) format, ...;
- (void) addMessageWithLevel: (int) level func: (const char *) func line: (int) line data: (NSData *) data format: (NSString *) format, ...;
- (void) addMessage: (NSString *) message;

- (void) clearLog;

@end


#endif
