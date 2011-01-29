/* (-*- objc -*-)
 * vxSync: cksum.h
 * Copyright (C) 2009-2010 Nathan Hjelm
 * v0.5.1
 *
 * Copying of this source file in part of whole without explicit permission is strictly prohibited.
 */

u_int16_t crc16_ccitt (u_int8_t *buf, size_t length);
u_int16_t crc16_ccitt2 (u_int8_t *buf, size_t length);
u_int32_t crc32 (u_int8_t *buf, size_t length);
u_int64_t crc64 (u_int8_t *buf, size_t length);
