/* (-*- objc -*-)
 * vxSync: VXSelectionView.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.8.2 - Feb 28, 2010
 *
 * View that does not hand any mouse events to subviews (makes icon's clickable). 
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#include "VXSelectionView.h"

@implementation VXSelectionView

- (void) dealloc {
  [self setDelegate: nil];
  [super dealloc];
}

- (id) delegate {
  return delegate;
}

- (void) setDelegate: (id) delegateIn {
  if (delegateIn != delegate) {
    [delegate release];
    delegate = [delegateIn retain];
  }
}

- (NSView *) hitTest: (NSPoint) aPoint {
  /* don't allow any mouse clicks for subviews in this view. this makes the icon clickable */
  if (NSPointInRect(aPoint,[self convertRect:[self bounds] toView:[self superview]]))
    return self;
  
  return nil;    
}
@end
