/*
 * This file is part of LibParserUtils.
 * Licensed under the MIT License,
 *                http://www.opensource.org/licenses/mit-license.php
 * Copyright 2007 John-Mark Bell <jmb@netsurf-browser.org>
 */

#ifndef parserutils_charset_codec_h_
#define parserutils_charset_codec_h_

#ifndef WIN32
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#else
typedef char  int8_t;
typedef short int16_t;
typedef int   int32_t;
typedef unsigned char  uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int   uint32_t;
typedef int bool;
#define false   (bool)0
#define true    (bool)1

#define INT8_MAX         127
#define INT16_MAX        32767
#define INT32_MAX        2147483647
#define INT64_MAX        9223372036854775807LL

#define INT8_MIN          -128
#define INT16_MIN         -32768
   /*
      Note:  the literal "most negative int" cannot be written in C --
      the rules in the standard (section 6.4.4.1 in C99) will give it
      an unsigned type, so INT32_MIN (and the most negative member of
      any larger signed type) must be written via a constant expression.
   */
#define INT32_MIN        (-INT32_MAX-1)
#define INT64_MIN        (-INT64_MAX-1)

#define UINT8_MAX         255
#define UINT16_MAX        65535
#define UINT32_MAX        4294967295U
#define UINT64_MAX        18446744073709551615ULL

#endif

#include <parserutils/errors.h>
#include <parserutils/functypes.h>

typedef struct parserutils_charset_codec parserutils_charset_codec;

#define PARSERUTILS_CHARSET_CODEC_NULL (0xffffffffU)

/**
 * Charset codec error mode
 *
 * A codec's error mode determines its behaviour in the face of:
 *
 * + characters which are unrepresentable in the destination charset (if
 *   encoding data) or which cannot be converted to UCS-4 (if decoding data).
 * + invalid byte sequences (both encoding and decoding)
 *
 * The options provide a choice between the following approaches:
 *
 * + draconian, "stop processing" ("strict")
 * + "replace the unrepresentable character with something else" ("loose")
 * + "attempt to transliterate, or replace if unable" ("translit")
 *
 * The default error mode is "loose".
 *
 *
 * In the "loose" case, the replacement character will depend upon:
 *
 * + Whether the operation was encoding or decoding
 * + If encoding, what the destination charset is.
 *
 * If decoding, the replacement character will be:
 *
 *     U+FFFD (REPLACEMENT CHARACTER)
 *
 * If encoding, the replacement character will be:
 *
 *     U+003F (QUESTION MARK) if the destination charset is not UTF-(8|16|32)
 *     U+FFFD (REPLACEMENT CHARACTER) otherwise.
 *
 *
 * In the "translit" case, the codec will attempt to transliterate into
 * the destination charset, if encoding. If decoding, or if transliteration
 * fails, this option is identical to "loose".
 */
typedef enum parserutils_charset_codec_errormode {
	/** Abort processing if unrepresentable character encountered */
	PARSERUTILS_CHARSET_CODEC_ERROR_STRICT   = 0,
	/** Replace unrepresentable characters with single alternate */
	PARSERUTILS_CHARSET_CODEC_ERROR_LOOSE    = 1,
	/** Transliterate unrepresentable characters, if possible */
	PARSERUTILS_CHARSET_CODEC_ERROR_TRANSLIT = 2
} parserutils_charset_codec_errormode;

/**
 * Charset codec option types
 */
typedef enum parserutils_charset_codec_opttype {
	/** Set codec error mode */
	PARSERUTILS_CHARSET_CODEC_ERROR_MODE  = 1
} parserutils_charset_codec_opttype;

/**
 * Charset codec option parameters
 */
typedef union parserutils_charset_codec_optparams {
	/** Parameters for error mode setting */
	struct {
		/** The desired error handling mode */
		parserutils_charset_codec_errormode mode;
	} error_mode;
} parserutils_charset_codec_optparams;


/* Create a charset codec */
parserutils_error parserutils_charset_codec_create(const char *charset,
		parserutils_alloc alloc, void *pw,
		parserutils_charset_codec **codec);
/* Destroy a charset codec */
parserutils_error parserutils_charset_codec_destroy(
		parserutils_charset_codec *codec);

/* Configure a charset codec */
parserutils_error parserutils_charset_codec_setopt(
		parserutils_charset_codec *codec,
		parserutils_charset_codec_opttype type, 
		parserutils_charset_codec_optparams *params);

/* Encode a chunk of UCS-4 data into a codec's charset */
parserutils_error parserutils_charset_codec_encode(
		parserutils_charset_codec *codec,
		const uint8_t **source, size_t *sourcelen,
		uint8_t **dest, size_t *destlen);

/* Decode a chunk of data in a codec's charset into UCS-4 */
parserutils_error parserutils_charset_codec_decode(
		parserutils_charset_codec *codec,
		const uint8_t **source, size_t *sourcelen,
		uint8_t **dest, size_t *destlen);

/* Reset a charset codec */
parserutils_error parserutils_charset_codec_reset(
		parserutils_charset_codec *codec);

#endif
