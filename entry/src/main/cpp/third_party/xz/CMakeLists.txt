# Decode-only liblzma (xz 5.6.2) built as a static library and linked into
# libdevbox_native.so. This provides .xz / .lzma decompression without
# depending on a system liblzma (none ships in the OHOS NDK sysroot).
#
# Sources are the upstream files (SPDX-License-Identifier: 0BSD, see
# COPYING.0BSD), trimmed to the decoder subset: no encoders, no threading,
# no lzip, no BCJ/delta filters. config.h is hand-written for this build.
cmake_minimum_required(VERSION 3.10)
project(devbox_lzma C)

set(CMAKE_C_STANDARD 99)

add_library(devbox_lzma STATIC
    liblzma/common/common.c
    liblzma/common/alone_decoder.c
    liblzma/common/auto_decoder.c
    liblzma/common/block_decoder.c
    liblzma/common/block_header_decoder.c
    liblzma/common/filter_common.c
    liblzma/common/filter_decoder.c
    liblzma/common/hardware_physmem.c
    liblzma/common/index.c
    liblzma/common/index_decoder.c
    liblzma/common/index_hash.c
    liblzma/common/stream_decoder.c
    liblzma/common/stream_flags_common.c
    liblzma/common/stream_flags_decoder.c
    liblzma/common/vli_decoder.c
    liblzma/common/vli_size.c
    liblzma/common/block_util.c
    liblzma/common/filter_flags_decoder.c
    liblzma/lzma/lzma_decoder.c
    liblzma/lzma/lzma2_decoder.c
    liblzma/lz/lz_decoder.c
    liblzma/check/check.c
    liblzma/check/crc32_fast.c
    liblzma/check/crc32_table.c
    liblzma/check/crc64_fast.c
    liblzma/check/crc64_table.c
    liblzma/check/sha256.c
    tuklib/tuklib_physmem.c
)

target_include_directories(devbox_lzma PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}          # config.h, tuklib_config.h
    ${CMAKE_CURRENT_SOURCE_DIR}/api      # lzma.h (public API)
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/common
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/lzma
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/lz
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/simple
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/delta
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/rangecoder
    ${CMAKE_CURRENT_SOURCE_DIR}/liblzma/check
    ${CMAKE_CURRENT_SOURCE_DIR}/tuklib
)

target_compile_definitions(devbox_lzma PRIVATE HAVE_CONFIG_H=1)

# Silence upstream warnings to keep the DevEco build output clean.
if(NOT CMAKE_C_FLAGS MATCHES "-Wno-")
    target_compile_options(devbox_lzma PRIVATE
        -Wno-unused-function
        -Wno-sign-compare
        -Wno-unused-parameter
    )
endif()

# 隐藏 lzma_* 符号: 静态链入 libdevbox_native.so, 不导出,
# 避免与系统/第三方 liblzma 的动态符号产生冲突 (同 .so 内链接不受影响)。
target_compile_options(devbox_lzma PRIVATE -fvisibility=hidden)
