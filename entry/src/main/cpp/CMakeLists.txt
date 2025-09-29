# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(mini_terminal)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH} ${NATIVERENDER_ROOT_PATH}/include)


add_subdirectory(freetype)

add_library(mini_terminal SHARED napi_init.cpp terminal.cpp)
target_link_libraries(mini_terminal PUBLIC libace_napi.z.so libGLESv3.so libEGL.so libnative_window.so libhilog_ndk.z.so freetype)