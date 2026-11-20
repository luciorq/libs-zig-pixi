# zig-toolchain: CMake toolchain file for x86_64-w64-mingw32 (zig -target x86_64-windows-gnu).
# Compilers and binutils are the zig-toolchain wrappers beside this file
# (<prefix>/bin). find_* looks ONLY in the private sub-prefix
# <envdir>/zig-libs/x86_64-windows-gnu for libraries, headers and packages, and NEVER
# there for programs, so the build env's perl, sqlite3, ... are found.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

get_filename_component(_ZT_BIN "${CMAKE_CURRENT_LIST_DIR}/../../bin" ABSOLUTE)
set(CMAKE_C_COMPILER   "${_ZT_BIN}/x86_64-w64-mingw32-cc")
set(CMAKE_CXX_COMPILER "${_ZT_BIN}/x86_64-w64-mingw32-c++")
set(CMAKE_AR           "${_ZT_BIN}/x86_64-w64-mingw32-ar" CACHE FILEPATH "")
set(CMAKE_RANLIB       "${_ZT_BIN}/x86_64-w64-mingw32-ranlib" CACHE FILEPATH "")
set(CMAKE_RC_COMPILER  "${_ZT_BIN}/x86_64-w64-mingw32-windres")
set(CMAKE_DLLTOOL      "${_ZT_BIN}/x86_64-w64-mingw32-dlltool" CACHE FILEPATH "")
# Never the build machine's ELF binutils (CMakeFindBinUtils would find
# /usr/bin/strip, nm, ...): strip is a no-op, the others fail with a clear
# message (zig has no COFF nm/objdump; add llvm-tools to the build env and
# set these per recipe if a project needs them). Linking goes through the
# compiler wrappers, never CMAKE_LINKER.
set(CMAKE_STRIP        "${_ZT_BIN}/x86_64-w64-mingw32-strip" CACHE FILEPATH "")
set(CMAKE_NM           "${_ZT_BIN}/x86_64-w64-mingw32-nm" CACHE FILEPATH "")
set(CMAKE_OBJDUMP      "${_ZT_BIN}/x86_64-w64-mingw32-objdump" CACHE FILEPATH "")
set(CMAKE_OBJCOPY      "${_ZT_BIN}/x86_64-w64-mingw32-objcopy" CACHE FILEPATH "")
set(CMAKE_READELF      "${_ZT_BIN}/x86_64-w64-mingw32-readelf" CACHE FILEPATH "")
set(CMAKE_ADDR2LINE    "${_ZT_BIN}/x86_64-w64-mingw32-addr2line" CACHE FILEPATH "")
set(CMAKE_LINKER       "${_ZT_BIN}/x86_64-w64-mingw32-ld" CACHE FILEPATH "")

# The sub-prefix: $ZIG_LIBS_PREFIX (activation script), else conda's host
# prefix layout.
if(DEFINED ENV{ZIG_LIBS_PREFIX} AND NOT "$ENV{ZIG_LIBS_PREFIX}" STREQUAL "")
  set(_ZT_LIBS "$ENV{ZIG_LIBS_PREFIX}")
else()
  set(_ZT_LIBS "$ENV{PREFIX}/Library/zig-libs/x86_64-windows-gnu")
endif()
set(CMAKE_FIND_ROOT_PATH "${_ZT_LIBS}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
