cmake_minimum_required(VERSION 3.22.1)
project("cw_audio" CXX)

add_library(cw_audio SHARED src/main/cpp/cw_tone_jni.cpp)

target_compile_options(cw_audio PRIVATE -std=c++17 -O2 -ffast-math)

# AAudio requires API 26+; aaudio and log are built into the NDK sysroot
target_link_libraries(cw_audio aaudio android log)
