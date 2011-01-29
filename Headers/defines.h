/* (-*- objc -*-)
 * vxSync: defines.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(DEFINES_H)
#define DEFINES_H

#define PersistentStoreDir @"Library/Application Support/vxSync/PersistentStore"

/* contact entities */
#define EntityContact               @"com.apple.contacts.Contact"
#define EntityAddress               @"com.apple.contacts.Street Address"
#define EntityEmail                 @"com.apple.contacts.Email Address"
#define EntityNumber                @"com.apple.contacts.Phone Number"
#define EntityGroup                 @"com.apple.contacts.Group"
#define EntityIM                    @"com.apple.contacts.IM"

/* calendar entities */
#define EntityEvent                 @"com.apple.calendars.Event"
#define EntityTask                  @"com.apple.calendars.Task"
#define EntityAudioAlarm            @"com.apple.calendars.AudioAlarm"
#define EntityDisplayAlarm          @"com.apple.calendars.DisplayAlarm"
#define EntityCalendar              @"com.apple.calendars.Calendar"
#define EntityRecurrence            @"com.apple.calendars.Recurrence"

/* notes */
#define EntityNote                  @"com.apple.notes.Note"

/* entity key */
#define RecordEntityName            @"com.apple.syncservices.RecordEntityName"

/* vxSync keys */
#define VXKeyPhoneIdentifier @"com.enansoft.vxSync.phone identifier"  /* identifier used by the phone (phone specific) */
#define VXKeyIndex           @"com.enansoft.vxSync.index"             /* index in the relevant file where this record exists (phone specific) */
#define VXKeyParentIndex     @"com.enansoft.vxSync.parent index"      /* index into parent's array (for example which index in the contact does this phone number reside) */
#define VXKeyIdentifier      @"com.enansoft.vxSync.identifier"        /* uuid used for communicating with the sync engine */
#define VXKeyPicturePath     @"com.enansoft.vxSync.picture path"      /* picture path on this phone (in set_as_pic_id on newer phones) */
#define VXKeyRingtonePath    @"com.vxSync.global.sound path"          /* GLOBAL: ringtone path */
#define VXKeyICEIndex        @"com.enansoft.vxSync.ice index"         /* index into ice entries (ice entry needs to be cleared on contact delete) */
#define VXKeyType            @"com.enansoft.vxSync.type"              /* record type (phone's POV) */
#define VXKeyOnPhone         @"com.enansoft.vxSync.onPhone"           /* record resides on phone */
#define VXKeyDirty           @"com.enansoft.vxSync.dirty"             /* record was modified by the sync engine */
#define VXKeyValue           @"com.enansoft.vxSync.value"             /* value on phone */
#define VXKeyUntilValue      @"com.enansoft.vxSync.until value"       /* for recurrences. this is the 32-bit value of the until field */
#define VXKeyDateCreated     @"com.enansoft.vxSync.date created"      /* creation date of an event */
#define VXKeyDateModified    @"com.enansoft.vxSync.date modified"     /* modification date of an event */
#define VXKeySpeedDial       @"com.vxSync.global.speed dial"          /* GLOBAL: speed dial setting 1-1000 */
#define VXKeyRingtoneIndex   @"com.enansoft.vxSync.ringtone index"
#define VXKeyPictureIndex    @"com.enansoft.vxSync.picture index"
#define VXKeyFavorites       @"com.enansoft.vxSync.favorite"          /* favorite contact */
#define VXKeyOnPhoneGroups   @"com.enansoft.vxSync.parent groups"     /* group relations that were synced to the phone */
#define VXKeyFullName        @"com.enansoft.full name"                /* full name for contact */

/* contact files */
#define VXPBEntryPath    @"pim/pbentry.dat"
#define VXPBNumberPath   @"pim/pbnumber.dat"
#define VXPBICEPath      @"pim/pbiceentry.dat"
#define VXPBSpeedPath    @"pim/pbspeed.dat"
#define VXPBGroupPath    @"pim/pbgroup.dat"
#define VXPBAddressPath  @"pim/pbaddress.dat"
#define VXPBPicureIDPath @"pim/pbPictureIdSetAsPath.dat"
#define VXPBRingerIDPath @"pim/pbRingIdSetAsPath.dat"
#define VXPBExtraPath    @"pim/pbvxSyncExtra.dat"
#define VXPBIMPath       @"pim/pbim.dat"
#define VXPBFavoritePath @"pim/pbFavorite.dat"
#define VXPBGroupPIXPath @"pim/pbGroupPixIdSetAsPath.dat"

#define kCarrierVerizon @"Verizon Wireless"
#define kCarrierTelus   @"Telus"
#define kCarrierBell    @"Bell Mobility"
#define kCarrierAlltel  @"Verizon Wireless"

/* schedule files */
#define VXSchedulePath   @"sch/schedule.dat"
#define VXExceptionPath  @"sch/schexception.dat"
#define VXMemoPath       @"sch/memo.dat"

#define kSecondsInDay      86400
#define kSecondsInWeek    604800
#define kSecondsInMonth  2678400 /* for 31 day month */
#define kSecondsInYear  31622400 /* for 366 day year */

#define kMaxSpeeds    1000
#define kMaxFavorites   10
#define kMaxGroups      30
#define kMaxICE          3
#define kMaxNumbers   5000
#define kMaxContacts  1000
#define kMaxAddresses 1000

#define vxEventUpdate  @"vxSyncRefreshDevices"
#define vxEventSync    @"vxSyncSync"
#define vxEventBackup  @"vxSyncBackup"
#define vxEventRestore @"vxSyncRestore"
#define vxEventScanBT  @"vxSyncScanBluetooth"

/* XXX -- todo -- change this back */
#define kBundleDomain @"com.enansoft.vxSync"

#define VXUTF16LEStringEncoding ((unsigned int)NSUTF16LittleEndianStringEncoding)

#define NS2CH(x) ([[(x) description] UTF8String])

enum { LGMemoFormat1, LGMemoFormat2 };
enum { LGPhonebookFormatStandard, LGPhonebookFormatStandardU, LGPhonebookFormatExtended, LGPhonebookFormatExtended2, LGPhonebookFormatExtended3 };
enum { LGGroupFormat1, LGGroupFormat2, LGGroupFormat3 };
enum { LGPhonenumberFormat1, LGPhonenumberFormat2 };

#endif
