//
//  NSDictionaryNoEmpty.m
//  vxSync
//
//  Created by Nathan Hjelm on 1/20/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "NSDictionaryNoEmpty.h"


@implementation NSDictionaryNoEmpty

- (BOOL)setSelectionIndexes:(NSIndexSet *)indexes {
  if (![indexes count])
    return NO;
  
  return [super setSelectionIndexes: indexes];
}

@end
