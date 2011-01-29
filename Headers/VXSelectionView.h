/* (-*- objc -*-)
 * vxSync: VXSelectionView.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(VXSELECTIONVIEW_H)
#define VXSELECTIONVIEW_H

#include <Cocoa/Cocoa.h>

@interface VXSelectionView : NSView {
  IBOutlet id delegate;
}

@property (retain) id delegate;

@end

#endif