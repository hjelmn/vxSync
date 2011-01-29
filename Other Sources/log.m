/* (-*- objc -*-)
 * vxSync: log.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.2
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#include "log.h"
#include "util.h"
#include "VXSync.h"

static vxSyncLogger *_defaultLogger = nil;
static NSString *levels[] = {@"errors only", @"errors + warnings", @"info", @"debug", @"debug + data"};
static NSString *levelMessage[] = {@"ERROR", @"WARNING", @"INFO", @"DEBUG", @"DATA"};

@interface vxSyncLogger (hidden)
- (void) setFile: (int) _fd;
- (void) addStringToController: (NSString *) logLine;
@end

@implementation vxSyncLogger

@synthesize logLevel, filehandle, prog, controller, logData, lineCounts, lock;

+ (vxSyncLogger *) defaultLogger {
  return _defaultLogger;
}

+ (void) setDefaultLogger: (vxSyncLogger *) logger {
  [_defaultLogger release];
  _defaultLogger = [logger retain];
}

+ (id) loggerWithLevel: (unsigned int) _level logFd: (int) _fd progName: (NSString *) _prog {
  return [[[vxSyncLogger alloc] initLogWithLevel: _level logFd: _fd progName: _prog] autorelease];
}

+ (id) loggerWithLevel: (unsigned int) _level controller: (NSArrayController *) _controller progName: (NSString *) _prog {
  return [[[vxSyncLogger alloc] initLogWithLevel: _level controller: _controller progName: _prog] autorelease];
}

- (void) setFile: (int) _fd {
  if (_fd < 0)
    return;

  [self setFilehandle: fdopen(_fd, "w")];
  setlinebuf ([self filehandle]);
}

- (void) setController: (NSArrayController *) _controller {
  [controller release];
  controller = [_controller retain];
  [self setLogData: [NSMutableArray array]];
  [self setLineCounts: [NSMutableArray array]];

  [self.controller setContent: self.logData];
}

- (void) setLogLevel: (unsigned int) level {
  if (level >= VXSYNC_LOG_LAST)
    level = VXSYNC_LOG_LAST - 1;
  
  logLevel = level;
  [self addMessage: [NSString stringWithFormat: @"Setting log level to: %d (%s)\n", self.logLevel, NS2CH(levels[self.logLevel])]];
}

/*
 initLogWithLevel:logFd:progName:
 
 the vxSyncLogger class will take ownership of the filedescriptor passed in it. the filedescriptor will be closed when the logger is deallocated (see dealloc)
*/
- (id) initLogWithLevel: (unsigned int) _level logFd: (int) _fd progName: (NSString *) _prog {
  self = [super init];
  if (!self)
    return nil;
  
  [self setLogLevel: _level];
  [self setFile: _fd];
  [self setProg: _prog];
  
  return self;
}

- (id) initLogWithLevel: (unsigned int) _level controller: (NSArrayController *) _controller progName: (NSString *) _prog {
  self = [super init];
  if (!self)
    return nil;
  
  [self setLogLevel: _level];
  [self setController: _controller];
  [self setProg: _prog];
  [self setLock: [[[NSLock alloc] init] autorelease]];
  
  return self;
}

- (void) dealloc {
  if (filehandle)
    fclose(filehandle);

  [self setLock: nil];
  [self setController: nil];
  [self setProg: nil];
  [self setLogData: nil];
  [self setLineCounts: nil];

  [self setFilehandle: NULL];
  
  [super dealloc];
}

- (NSString *) generateLogMessageWithLevel: (int) level func: (const char *) func line: (int) line format: (NSString *) format args: (va_list) arg {
  NSString *format2;
  ssize_t len;
  char *str = NULL;

  format2 = [NSString stringWithFormat: @"%@ %s(%i) %@: %@", self.prog, func, line, level > 0 ? levelMessage[level] : @"INFO", format];
  len = vasprintf (&str, [format2 UTF8String], arg);

  if (len < 1 || !str)
    return nil; /* could not allocate memory for log message. can't continue */
  
  /* NSString will deallocate the str pointer */
  return [[[NSString alloc] initWithBytesNoCopy: str length: len encoding: NSUTF8StringEncoding freeWhenDone: YES] autorelease];
}

- (void) addMessageWithLevel: (int) level func: (const char *) func line: (int) line format: (NSString *) format, ... {
  va_list arg;

  if (level > (int)self.logLevel)
    return;
  
  va_start (arg, format);
  [self addMessage: [self generateLogMessageWithLevel: level func: func line: line format: format args: arg]];
  va_end (arg);
}

- (void) addMessageWithLevel: (int) level func: (const char *) func line: (int) line data: (NSData *) data format: (NSString *) format, ... {
  NSString *message;
  va_list arg;

  if (level > (int)self.logLevel)
    return;
  
  va_start (arg, format);
  message = [self generateLogMessageWithLevel: level func: func line: line format: format args: arg];
  va_end (arg);
  
  if (message)
    [self addMessage: [NSString stringWithFormat: @"%@%@", message, data]];
}

- (void) addMessage: (NSString *) message {
  if (!message)
    return;

  if (self.filehandle) {
    fprintf (self.filehandle, "%s", [message UTF8String]);
    fputc('\n', filehandle); /* insert another newline to tell vxSync where the log message ends */
  } else if (self.controller)
    [self addStringToController: message];
}

- (void) addStringToController: (NSString *) logLine {
  NSArray *components = [logLine componentsSeparatedByString: @"\n"];
  int rows = [components count];
  
  /* rows should be how many times the current string would need to
   be split to fit in the current width */
  if ([(NSString *)[components objectAtIndex: [components count] - 1] length] == 0)
    rows--;
  
  [lock lock];
  /* store line counts to simplify the table view delegate. this *must* be done before adding the string to the controller */
  [lineCounts addObject: [NSNumber numberWithInt: rows]];

  [controller addObject: logLine];
  
  usleep(10000);
  [lock unlock];
}

@end
