cmake_minimum_required(VERSION 3.10)
project(devbox_native)

set(CMAKE_CXX_STANDARD 17)

add_library(devbox_native SHARED
    shell_exec.cpp
    napi_bridge.cpp
    archive_extract.cpp
)

target_include_directories(devbox_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

find_library(NAPI_LIB ace_napi.z)
find_library(HILOG_LIB hilog_ndk.z)

# ---- gzip 解压: OHOS NDK sysroot 自带 zlib (zlib.h 1.3.1 + libz.so) ----
find_library(ZLIB_LIB z)
if(NOT ZLIB_LIB)
    message(FATAL_ERROR "zlib (libz) not found in NDK toolchain sysroot")
endif()

# ---- xz 解压: 优先系统 liblzma (当前 OHOS sysroot 没有), 否则用内置 decode-only 源码 ----
include(CheckIncludeFile)
check_include_file("lzma.h" HAVE_SYSTEM_LZMA_H)
find_library(LZMA_LIB lzma)
if(LZMA_LIB AND HAVE_SYSTEM_LZMA_H)
    # 选项 B: 系统 liblzma (若未来 NDK 提供)
    message(STATUS "devbox_native: using system liblzma (${LZMA_LIB})")
    target_compile_definitions(devbox_native PRIVATE DEVBOX_HAVE_LZMA=1)
    target_link_libraries(devbox_native ${LZMA_LIB})
else()
    # 选项 A: 内置 decode-only liblzma 5.6.2 (third_party/xz, 0BSD)
    message(STATUS "devbox_native: using bundled decode-only liblzma")
    add_subdirectory(third_party/xz)
    target_compile_definitions(devbox_native PRIVATE DEVBOX_HAVE_LZMA=1)
    target_link_libraries(devbox_native devbox_lzma)
endif()

target_link_libraries(devbox_native ${NAPI_LIB} ${HILOG_LIB} ${ZLIB_LIB})
