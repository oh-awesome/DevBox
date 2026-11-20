// SPDX-License-Identifier: 0BSD
//
// Hand-written configuration for the bundled decode-only liblzma subset.
// This replaces the config.h normally produced by xz's configure script.
//
// Target: HarmonyOS NDK (aarch64-linux-ohos, musl libc, clang).
// Scope:  .xz / .lzma decoding only (lzma_stream_decoder / lzma_auto_decoder).
//         No encoders, no threading, no lzip, no BCJ/delta filters.
// Source: xz 5.6.2 (https://tukaani.org/xz/), see COPYING.0BSD.
#ifndef LZMA_CONFIG_H
#define LZMA_CONFIG_H

//////////////
// Threads //
//////////////

// Single-threaded build. stream_decoder_mt / *_mt APIs are not compiled in.
#define MYTHREAD_ENABLED 0

/////////////////
// System deps //
/////////////////

// OHOS musl provides the C99 headers.
#define HAVE_STDBOOL_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE__BOOL 1

// Keep symbols hidden by default; the CMake build controls visibility.
#define HAVE_VISIBILITY 0

// clang supports these builtins.
#define HAVE___BUILTIN_ASSUME_ALIGNED 1

// 64-bit target.
#define SIZEOF_SIZE_T 8

////////////////////
// Integrity checks //
////////////////////

// xz archives commonly use CRC64; sha256 needed for archives that select it.
#define HAVE_CHECK_CRC32 1
#define HAVE_CHECK_CRC64 1
#define HAVE_CHECK_SHA256 1

// sha256.c falls back to the built-in implementation (no system SHA macros).

//////////////
// Decoders //
//////////////

#define HAVE_DECODERS 1
#define HAVE_DECODER_LZMA1 1
#define HAVE_DECODER_LZMA2 1
#define HAVE_DECODER_ALONE 1

// Not enabled: HAVE_DECODER_DELTA, HAVE_DECODER_X86/ARM/ARM64/... (BCJ),
// HAVE_LZIP_DECODER, HAVE_ENCODERS. Archives using those filters will be
// reported as unsupported via LZMA_OPTIONS_ERROR / LZMA_FORMAT_ERROR.

//////////////////
// Miscellaneous //
//////////////////

// Fallback RAM assumption when tuklib_physmem() cannot detect the amount
// (only used for default decoder memory limits; we pass UINT64_MAX anyway).
#define ASSUME_RAM 128

#endif
