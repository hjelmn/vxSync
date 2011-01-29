/* (-*- objc -*-)
 * vxSync: LGPBFavorites.h
 * Copyright (C) 2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

#if !defined(LGPBFAVORITES_H)
#define LGPBFAVORITES_H

#include "LGPBEntryFile.h"

@interface LGPBEntryFile (Favorites)

- (BOOL) supportsFavorites;

- (int) readFavorites;
- (int) writeFavorites;

- (NSArray *) getEntryFavorites;
- (int) setEntryFavorites: (NSArray *) fav;

@end

#endif