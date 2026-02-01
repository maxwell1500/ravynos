cmake_minimum_required(VERSION 3.15.1)
project(kextcache)

# ------------------------------------------------------------------------
#                        PRODUCT VERSION KNOBS
# ------------------------------------------------------------------------
set(CMAKE_MACOSX_MIN_VERSION 11.0)

# ------------------------------------------------------------------------

set(CMAKE_INSTALL_PREFIX "")

add_executable(kextcache)
target_compile_options(kextcache PRIVATE -mmacos-version-min=11.0 -Wnone -w
    #-DOS_ASSUME_PTR_ABI_SINGLE_BEGIN=
    #-DOS_ASSUME_PTR_ABI_SINGLE_END=
    #-DOS_UNSAFE_INDEXABLE=
)

target_sources(kextcache PRIVATE bootcaches.c brtest.c kextcache_main.c mkext1_file.c update_boot.c)
target_include_directories(kextcache PRIVATE
    3rd 
    include 
    ../../ravynos/Kernel/xnu/libkern
)
