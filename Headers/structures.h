/* (-*- objc -*-)
 * vxSync: structures.h
 * Copyright (C) 2009-2011 Nathan Hjelm
 * v0.8.4
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

#if !defined(STRUCTURES_H)
#define STRUCTURES_H

#include <sys/types.h>

/**** begin: data structures ****/
/* original 256 byte phonebook entry */
struct lg_entry {
  char      entry_tag[5];
  u_int16_t mod_date[6];
  u_int8_t  unknown0[6];       /* 0xffffffffffff */
  u_int32_t entry_id;
  u_int16_t entry_index;
  char      name[33];
  u_int16_t group_id;
  char      emails[2][49];
  u_int16_t ringtone_id;       /* 0xffff == not set */
  u_int16_t picture_id;        /* 0x0000 == not set */
  u_int8_t  number_types[5];
  u_int16_t number_indices[5];
  u_int8_t  unknown1[69];
  char      exit_tag[6];
} __attribute__ ((__packed__));

/* first seen on a VX-5500 */
struct lg_entry_unicode {
  char      entry_tag[5];
  u_int16_t mod_date[6];
  u_int8_t  unknown0[6];       /* 0xffffffffffff */
  u_int32_t entry_id;
  u_int16_t entry_index;
  char      name[66];          /* unicode formatted (bizarre) */
  u_int16_t group_id;
  char      emails[2][49];
  u_int16_t ringtone_id;       /* 0xffff == not set */
  u_int16_t picture_id;        /* 0x0000 == not set */
  u_int8_t  number_types[5];
  u_int16_t number_indices[5];
  u_int8_t  unknown1[36];
  char      exit_tag[6];
} __attribute__ ((__packed__));

/* extended 512 byte phonebook entry */
struct lg_entry_ex {
  char      entry_tag[5];
  u_int8_t  unknown0;          /* 0xff */
  u_int16_t mod_date[6];
  u_int8_t  unknown1[6];       /* 0xffffffffffff */
  u_int32_t entry_id;
  u_int16_t entry_index;
  char      name[34];
  u_int16_t group_ids[30];
  char      emails[2][49];
  u_int16_t ringtone_id;       /* 0xffff == not set */
  u_int16_t picture_id;        /* 0x0000 == not set */
  u_int8_t  number_types[5];
  u_int8_t  unknown3;          /* 0x00 */
  u_int16_t number_indices[5];
  u_int16_t address_index;     /* 0xffff == not set */
  u_int16_t unknown4;          /* 0xffff */
  u_int8_t  unknown5[260];
  char      exit_tag[6];
} __attribute__ ((__packed__));

/* extended 512 byte phonebook entry */
struct lg_entry_ex_v2 {
  char      entry_tag[5];
  u_int8_t  unknown0;          /* 0xff */
  u_int16_t mod_date[6];
  u_int8_t  unknown1[6];       /* 0xffffffffffff */
  u_int32_t entry_id;
  u_int16_t entry_index;
  char      name[34];
  u_int16_t group_ids[30];
  char      emails[2][49];
  u_int16_t ringtone_id;       /* 0xffff == not set */
  u_int16_t picture_id;        /* 0x0000 == not set */
  u_int8_t  number_types[5];
  u_int8_t  unknown3[3];       /* 0x000000 */
  u_int16_t number_indices[5];
  u_int16_t address_index;     /* 0xffff == not set */
  u_int16_t unknown4;          /* 0xffff */
  u_int32_t im_index;          /* 0xffff == not set */
  u_int8_t  unknown5[256];
  char      exit_tag[6];
} __attribute__ ((__packed__));

/* one hpe entry follows phonebook entries */
struct lg_hpe_ex {
  char      entry_tag[6];
  char      model_id[10];
  u_int16_t mod_date[6];
  u_int8_t  unknown0[477];
  char      exit_tag[7];
} __attribute__ ((__packed__));

struct lg_hpe {
  char      entry_tag[6];
  char      model_id[10];
  u_int16_t mod_date[6];
  u_int8_t  unknown0[221];
  char      exit_tag[7];
} __attribute__ ((__packed__));

struct lg_group {
  char name[33];
  u_int16_t groupid;
  u_int8_t isDeletable; /* probably not a deleteablity flag! */
  /* occational 2 byte padding */
} __attribute__ ((__packed__));

struct lg_group_unicode {
  char name[66];
  u_int16_t groupid;
  u_int8_t isDeletable; /* probably not a deleteablity flag! */
  u_int8_t unknown0;    /* 0 */
} __attribute__ ((__packed__));

/* 64 byte phonenumber entry */
struct lg_number {
  char entry_tag[5];
  u_int16_t mod_date[6];
  u_int8_t  unknown0[6];
  u_int16_t number_index;
  u_int16_t entry_index;
  u_int8_t  parent_index;
  unsigned char data[25];
  u_int8_t  type;
  u_int32_t unknown1; /* 0 */
  char exit_tag[6];
} __attribute__ ((__packed__));

struct lg_number_type2 {
  char entry_tag[5];
  u_int8_t  unknown2; /* 0 */
  u_int16_t mod_date[6];
  u_int8_t  unknown0[6];
  u_int16_t number_index;
  u_int16_t entry_index;
  u_int8_t  parent_index;
  u_int8_t  unknown3; /* 0 */
  unsigned char data[25];
  u_int8_t  unknown4; /* 0 */
  u_int8_t  type;
  u_int8_t unknown1; /* 0 */
  char exit_tag[6];
} __attribute__ ((__packed__));


/* extended data */
struct lg_address {
  char      entry_tag[5];
  u_int8_t  unknown0; /* 0x00 */
  u_int16_t mod_date[6];
  u_int8_t  unknown1[6]; /* 0 */
  u_int16_t address_index;
  u_int16_t entry_index;
  char      street[52];
  char      city[52];
  char      state[52];
  char      zip[13];
  char      country[52];
  char      exit_tag[6];
} __attribute__ ((__packed__));

struct lg_ice_entry {
  u_int16_t is_assigned; /* 0 or 1 */
  u_int16_t ice_index;   /* index in the ice file */
  u_int16_t entry_index; /* phonebook entry */
  u_int8_t  data[82];    /* 0 */
} __attribute__ ((__packed__));

struct lg_im_entry {
  char      entry_tag[5]; /* <PI>\0 */
  u_int8_t  unknown0;     /* 0x00 */
  u_int16_t mod_date[6];
  u_int8_t  unknown1[6];  /* 0 */
  u_int16_t im_index;
  u_int16_t entry_index;
  u_int16_t service;      /* 0 = aim, 1 = yahoo, 2 = windows live */
  char      user[43];
  u_int8_t  unknown2[49]; /* 0 */
  char      exit_tag[6];  /* </PI>\0 */
};

struct lg_schedule_event {
  u_int32_t offset;
  char      summary[33];
  u_int32_t ctime;
  u_int32_t mtime;
  u_int32_t start_date;
  u_int32_t end_date;
  u_int32_t recurrence_end; /** Good name? Bad name? Who knows XXX -- I should */
  u_int32_t recurrence;     /* 0 - no recurrence */
  u_int8_t  alarm;
  u_int8_t  ringtone_index;
  u_int8_t  unknown1;
  u_int8_t  minutes_before;
  u_int8_t  hours_before;
  u_int8_t  unknown2;
  u_int16_t unknown3;      /* 0x01fc has been seen */
  u_int32_t unknown4;      /* usually 0 */
  u_int8_t  extra_data[65];    /* first 37 bytes appears to be a uuid (we can use this :D i hope) */
} __attribute__ ((__packed__));

struct lg_schedule_exception {
  u_int32_t offset;
  u_int8_t  day;
  u_int8_t  month;
  u_int16_t year;
} __attribute__ ((__packed__));

struct lg_memo_type_1 {
  u_int32_t cdate;     /* time since Jan 6 1980 00:00:00 */
  char      memo[301];
  u_int32_t mdate;     /* lg date format */
  u_int8_t  pad[3];    /* 0x000000 */
} __attribute__ ((__packed__));

/* Voyager/Venus */
struct lg_memo_type_2 {
  u_int32_t cdate;
  char      memo[304];
  u_int32_t mdate;
} __attribute__ ((__packed__));

/* there are 10 favorites on all known phones -- this will probably change in the future */
struct lg_favorite {
  u_int16_t favindex;
  u_int8_t  groupFlag;
} __attribute__ ((__packed__));

/* there are 10 favorites on the Versa. the first favorite is proceeded by a uint16 containing the number of set favorites.
   there does not appear to be a way to set a group as a favorite as is possible with newer phones. */
struct lg_favorite_versa {
  u_int16_t unk0;     /* 0x0000 -- when favorite set, 0xffff otherwise */
  u_int16_t favindex; /* phonebook entry index. 0xffff if not set */
  u_int8_t  unk1[4];  /* unknown: 0x00000000 when set, 0xffffffff otherwise */
  u_int16_t unk2;     /* unknown: 0x0045 when set, 0xffff otherwise */
  u_int8_t  unk3[2];  /* unknown: 0x0000 when set, 0xffff otherwise */
};

/* 0xf1 xx:                                                                                          
 0x01 -- read current network
 0x0a -- phone info

 30: Call log
 0x1e -- unknown
 0x1f -- start iterator. index: 0 - all, 1 -- received, 2 -- dialed, 3 -- data?
 0x20 -- advance iterator
 0x21 -- clear call logs. index: 0 - all, 1 -- received, 2 -- dialed, 3 -- data 
 0x22-0x27 -- no command

 40: Phonebook
 0x28 -- init?
 0x29 -- read contact
 0x2a -- write contact
 0x2b -- delete contact
 0x2c -- read picture id. index = phone entry index
 0x2d -- read built-in ringtone name
 0x2e -- read groups (group id goes in byte 10)
 0x2f -- erase all contacts
 0x30 -- unknown (phone responds)
 0x31 -- no command

 50: Calendar
 0x32 -- read event
 0x33 -- write event
 0x34 -- delete event
 0x35 -- clear all events
 0x36-0x3b -- no command
 
 60: Unknown
 0x3c-0x3d -- unknown (phone responds)
 0x3e-0x45 -- no command

 70: Settings
 0x46-0x48 -- unknown (phone responds)
 0x49 -- reset phone setting to factory and reboot
 */

struct lg_pbv1_standard {
  u_int8_t  command;        /* 0xf1 */
  u_int8_t  option;         /* 0x2a == write 0x28 == init read, 0x2f == init write, etc */
  u_int16_t index;          /* */
  u_int8_t  unknown0[6];    /* 00 00 00 00 00 00 */
  char      name[33];       /* contact name (iso-latin 1) */
  u_int16_t gid;            /* 0(no group)-30 */
  char      emails[2][49];  /* contact emails */
  u_int8_t  unknown1[6];    /* 00 00 00 00 00 00 */
  char      numbers[5][49]; /* mobile1, home, work, mobile2, fax */
  u_int16_t default_number; /* 1-5 (index in previous array + 1) */
  u_int8_t  unknown2[96];   /* doesn't matter */
  u_int16_t validflag;      /* 0x012f == invalid, 0x0000 == valid */
} __attribute__ ((__packed__));

struct lg_pbv1_standard_choct {
  u_int8_t  command;        /* 0xf1 */
  u_int8_t  option;         /* 0x2a == write 0x28 == init read, 0x2f == init write, etc */
  u_int16_t entry_index;    /* */
  u_int8_t  unknown0[6];    /* 00 00 00 00 00 00 */
  char      name[33];       /* contact name (iso-latin 1) */
  u_int16_t gid;            /* 0(no group)-30 */
  char      emails[2][49];  /* contact emails */
  u_int16_t ringtone_index; /* ringtone index - 0xffff = not set */
  u_int16_t unknown1;       /* 0xffff */
  u_int16_t picture_index;  /* picture index - 0xffff = not set */
  char      numbers[5][49]; /* mobile1, home, work, mobile2, fax */
  u_int16_t primary_number; /* 1-5 (index in previous array + 1) */
  u_int8_t  unknown2[73];   /* doesn't matter */
  u_int16_t mod_date[6];    /* */
  u_int8_t  unknown3[6];    /* */
  char      street[51];     /* */
  char      city[51];       /* */
  char      state[51];      /* */
  char      zip[12];        /* */
  char      country[51];    /* */
  u_int16_t im_service;     /* 0 = AIM, 1 = Yahoo!, 2 = Windows Live */
  char      user[43];       /* im username */
  u_int8_t  unknown4[6];    /* 0 */
} __attribute__ ((__packed__));

struct lg_pbv1_standard_accolade {
  u_int8_t  command;        /* 0xf1 */
  u_int8_t  option;         /* 0x2a == write 0x28 == init read, 0x2f == init write, etc */
  u_int16_t entry_index;    /* */
  u_int8_t  unknown0[6];    /* 00 00 00 00 00 00 */
  char      name[33];       /* contact name (iso-latin 1) */
  u_int16_t gid;            /* 0(no group)-30 */
  char      emails[2][49];  /* contact emails (home, work) */
  u_int16_t ringtone_index; /* ringtone index - 0xffff = not set */
  u_int16_t unknown1;       /* 0xffff */
  u_int16_t picture_index;  /* picture index - 0xffff = not set */
  char      numbers[5][49]; /* mobile1, home, work, mobile2, fax */
  u_int16_t primary_number; /* 1-5 (index in previous array + 1) */
  u_int8_t  unknown2[73];   /* doesn't matter */
  u_int16_t mod_date[6];    /* */
  u_int8_t  unknown3[6];    /* */
  char      street[33];     /* */
  char      city[33];       /* */
  char      state[33];      /* */
  char      zip[12];        /* */
  char      country[33];    /* */
  u_int16_t im_service;     /* 0 = AIM, 1 = Yahoo!, 2 = Windows Live */
  char      user[49];       /* im username */
  char      note[31];       /* contact note */
  u_int8_t  unknown4[6];    /* 0 */
} __attribute__ ((__packed__));

struct lg_pbv1_unicode {
  u_int8_t  command;        /* 0xf1 */
  u_int8_t  option;         /* 0x2a == write 0x28 == init read, 0x2f == init write, etc */
  u_int16_t index;          /* */
  u_int8_t  unknown0[6];    /* 00 00 00 00 00 00 */
  u_int16_t name[33];       /* contact name (utf-16 le) */
  u_int16_t gid;            /* 0(no group)-30 */
  char      emails[2][49];  /* contact emails */
  u_int8_t  unknown1[6];    /* 00 00 00 00 00 00 */
  char      numbers[5][49]; /* mobile1, home, work, mobile2, fax */
  u_int16_t default_number; /* 1-5 (index in previous array + 1) */
  u_int8_t  unknown2[96];   /* doesn't matter */
  u_int16_t validflag;      /* 0x012f == invalid, 0x0000 == valid */
} __attribute__ ((__packed__));


/*
  all dates are year, month, day, hour, min
*/
#if 0
struct lg_pb_event {
  u_int8_t  command;        /* 0xf1 */
  u_int8_t  option;         /* see commands above */
  u_int16_t index;          /* */
  u_int8_t  unknown0[8];    /* 00 00 00 00 00 00 */
  u_int16_t name[33];       /* contact name (utf-16 le) */
  u_int16_t mdate[9];       /* or cdate (GMT) */
  u_int16_t cdate[9];       /* or mdate (GMT) */
  u_int8_t  uuid[64];       /* or less */
  u_int16_t start[9];       /* event start (GMT) */
  u_int16_t end[9];         /* event end (GMT) */
  struct {
    u_int8_t  type;         /* 1 - daily, 2 - weekly, 3 - monthly, 4 - yearly */
    u_int16_t frequency;
    u_int8_t  unknown0[2];
    u_int16_t end[9];
    u_int8_t  unknown1[11];
    u_int8_t  flag1;        /* set when repeating on the same day of the month? */
    u_int8_t  unknown2[2];
    u_int8_t  day_mask;     /* high bit is not used? */
    u_int8_t  week;         /* */
  } __attribute__ ((__packed__)) repeat;
  u_int8_t  repeat_type

  u_int16_t gid;            /* 0(no group)-30 */
  char      emails[2][49];  /* contact emails */
  u_int8_t  unknown1[6];    /* 00 00 00 00 00 00 */
  char      numbers[5][49]; /* mobile1, home, work, mobile2, fax */
  u_int16_t default_number; /* 1-5 (index in previous array + 1) */
  u_int8_t  unknown2[96];   /* doesn't matter */
  u_int16_t validflag;      /* 0x012f == invalid, 0x0000 == valid */
} __attribute__ ((__packed__));
#endif
/**** end: data structures ****/

struct _devices {
  NSString *deviceID;
  NSString *deviceString;
  NSString *carrier;
  int memoFormat;
  int phonebookFormat;
  BOOL unicodePhonebook;
  int pictureIDwidth, pictureIDheight;
  int groupFormat;
  NSString *deviceImagePath;

  int memoLimit;
  int contactLimit;
  int eventLimit;
  int taskLimit;
  int groupLimit;
};

struct notification_data {
  NSLock *lock;
  NSMutableArray *list;
};

#endif
