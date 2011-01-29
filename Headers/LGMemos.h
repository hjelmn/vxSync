/* (-*- objc -*-)
 * vxSync: LGMemos.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.6.4
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(LGMEMO_H)
#define LGMEMO_H

#include "VXSync.h"
#include "vxPhone.h"

@interface LGMemos : NSObject <LGData> {
@private
  vxPhone *phone;

  id <LGDataDelegate> delegate;
  int memoFormat, memoLimit;

  NSMutableDictionary *internalRecords;
}

@property (retain) vxPhone *phone;
@property (retain) id <LGDataDelegate> delegate;
@property (retain) NSMutableDictionary *internalRecords;

@end

#endif
