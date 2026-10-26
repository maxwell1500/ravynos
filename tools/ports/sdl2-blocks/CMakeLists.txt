cmake_minimum_required(VERSION 3.20)
project(SDLBlocks LANGUAGES C)

# A deliberately ordinary SDL2 program: nothing here knows about ravynOS.  It
# finds SDL2 through pkg-config and zlib through CMake's own module, which is
# exactly how a Linux/BSD SDL2 application is built, and that is the point --
# if this port needed ravynOS-specific flags it would not prove the SDK works.

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)
find_package(ZLIB REQUIRED)

add_executable(SDLBlocks main.c)
target_link_libraries(SDLBlocks PRIVATE PkgConfig::SDL2 ZLIB::ZLIB)
target_compile_options(SDLBlocks PRIVATE -Wall)

# Install as an ordinary unix binary; build_port.py wraps it into an .app.
include(GNUInstallDirs)
install(TARGETS SDLBlocks RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
