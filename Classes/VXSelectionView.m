/* (-*- objc -*-)
 * vxSync: VXSelectionView.m
 * (C) 2009-2011 Nathan Hjelm
 *
 * v0.8.2 - Feb 28, 2010
 *
 * View that does not hand any mouse events to subviews (makes icon's clickable). 
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
