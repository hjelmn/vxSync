/* (-*- objc -*-)
 * vxSync: VX_SyncPref.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
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

#if !defined(VX_SYNCPREF_H)
#define VX_SYNCPREF_H

#include "VXSync.h"

#include "KNShelfSplitView.h"
#include "vxAvailableTransformer.h"

@interface VX_SyncPref : NSPreferencePane {
  /* interface builder outlets */
  IBOutlet NSTextField    *versionField;
  IBOutlet NSBox          *phoneInfo;
  IBOutlet NSView         *phoneViewer, *calendarView, *noteView, *contactView;
  
  IBOutlet NSProgressIndicator *progIndicator;
  IBOutlet NSProgressIndicator *btScanIndicator;
  IBOutlet NSProgressIndicator *updateIndicator;
  
  IBOutlet NSTextField *btScanStatus;
  
  IBOutlet NSPanel        *addPanel;
  IBOutlet NSWindow       *mainWindow;
    
  IBOutlet NSCollectionView *collectionView;
  IBOutlet NSArrayController /* *fKnownDevicesController , *fUnknownDevicesController */ *categoryController, *syncModesController;

  IBOutlet NSDictionaryController *fUnknownDevicesController, *fKnownDevicesController;
  
  IBOutlet KNShelfSplitView *splitView;
  IBOutlet NSScrollView *scrollView, *deviceScrollView;

  IBOutlet NSTextField *actionStatus;

  /* properites */
//  NSMutableArray *fKnownDevices, *fUnknownDevices;
  NSMutableDictionary *fKnownDevices, *fUnknownDevices;
  NSArray *categories, *syncModes;
  
@private
  int logLevel;
  BOOL isBusy, doWork, useBluetooth;
  struct notification_data nData;
  int message;
  NSString *restoreFilename;
  NSThread *workThread;
  NSDate *lastScan;
  
  NSPredicate *newEventCalendarFilter;
}

@property (retain) NSMutableDictionary *fKnownDevices;
//@property(retain) NSMutableArray *fKnownDevices;
@property(retain) NSMutableDictionary *fUnknownDevices;
//@property(retain) NSMutableArray *fUnknownDevices;
@property(retain) NSArray *categories;
@property(retain) NSArray *syncModes;
@property BOOL useBluetooth;
@property(retain) NSPredicate *newEventCalendarFilter;
@property int message;

- (id) initWithBundle: (NSBundle *) bundle;
- (void) mainViewDidLoad;

/* interface builder actions */
/* device management */
- (IBAction) addDevice:(id)sender;
- (IBAction) removeDevice:(id)sender;
- (IBAction) doAddDevice:(id)sender;
- (IBAction) doCancelAddDevice:(id)sender;

/* donate button */
- (IBAction) doDonate: (id) sender;

/* device backup */
- (IBAction) backupDevice:(id)sender;
- (IBAction) restoreDevice:(id)sender;

/* sync */
- (IBAction) sync: (id) sender;

@property (retain) NSTextField    *versionField;
@property (retain) NSBox          *phoneInfo;
@property (retain) NSProgressIndicator *progIndicator;
@property (retain) NSPanel        *addPanel;
@property (retain) NSWindow       *mainWindow;
@property (retain) NSCollectionView *collectionView;
@property (retain) KNShelfSplitView *splitView;
@property (retain) NSTextField *actionStatus;
@property int logLevel;
@property BOOL isBusy;
@property (retain) NSString *restoreFilename;
@end

#endif
