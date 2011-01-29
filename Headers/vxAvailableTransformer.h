/* (-*- objc -*-)
 * vxSync: vxAvailableTransformer.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(VXAVAILABLETRANSFORMER_H)
#define VXAVAILABLETRANSFORMER_H

#import <Cocoa/Cocoa.h>

#include "util.h"

@interface vxAvailableTransformer : NSValueTransformer {
  id dontcare;
}
+ (Class)transformedValueClass;
+ (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)beforeObject;
@end

@interface vxAvailableTransformerText : NSValueTransformer {
  id dontcare;
}
+ (Class)transformedValueClass;
+ (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)beforeObject;
@end

@interface noSelectionTransformer : NSValueTransformer {
  id dontcare;
}
+ (Class)transformedValueClass;
+ (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)beforeObject;
@end


#endif
