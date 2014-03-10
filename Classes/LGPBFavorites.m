/* (-*- objc -*-)
 * vxSync: LGPBFavorites.m
 * Copyright (C) 2010-2011 Nathan Hjelm
 * v0.8.2
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

#include "LGPBFavorites.h"


@implementation LGPBEntryFile (Favorites)

- (BOOL) supportsFavorites {
  return NO;
}

- (int) readFavorites {
  NSMutableArray *newfavorites;
  NSData *favoritesData;
  struct lg_favorite *faves;
  int count, i;
  NSString *error;
  
  if (![self supportsFavorites])
    return -2;
  
  favoritesData = [[phone efs] get_file_data_from: VXPBFavoritePath errorOut: &error];
  if (nil == favoritesData) {
    vxSync_log3(VXSYNC_LOG_WARNING, @"could not read favorites: %s\n", NS2CH(error));
    
    return -1;
  }
  
  newfavorites = [NSMutableArray array];
  
  faves = (struct lg_favorite *) [favoritesData bytes];
  count = [favoritesData length] / sizeof (struct lg_favorite);
  
  for (i = 0 ; i < count ; i++) {
    if (faves[i].favindex != 0xffff) {
      NSMutableDictionary *fav = [NSMutableDictionary dictionaryWithCapacity: 3];
      
      [fav setObject: [NSNumber numberWithUnsignedShort: faves[i].favindex] forKey: @"favorite index"];
      [fav setObject: faves[i].groupFlag ? EntityGroup : EntityContact forKey: @"entity"];
      [fav setObject: [NSNumber numberWithInt: i] forKey: VXKeyIndex];
      
      [newfavorites addObject: fav];
    }
  }
  
  [self setFavorites: newfavorites];

  return 0;
}

- (int) writeFavorites {
  NSMutableData *favoritesData = [NSMutableData dataWithLength: 30];
  unsigned char *favoritesBytes = (unsigned char *)[favoritesData bytes];
  
  for (id fav in favorites) {
    int favindex = [[fav objectForKey: VXKeyIndex] intValue];
    if (favindex < 10) {
      OSWriteLittleInt16 (favoritesBytes, 3 * favindex, [[fav objectForKey: @"favorite index"] unsignedShortValue]);
      if ([[fav objectForKey: @"entity"] isEqualToString: EntityGroup])
        favoritesBytes[3 * favindex + 2] = 1;
    }
  }
  
  [[phone efs] write_file_data: favoritesData to: VXPBFavoritePath];
  
  return 0;
}

- (NSArray *) getEntryFavorites {
//  NSMutableArray *entryFavorites = [NSMutableArray array];
  
  for (id fav in favorites) {
    
  }
  
  
  return nil;
}

- (int) setEntryFavorites: (NSArray *) fav {
  return -1;
}

@end
