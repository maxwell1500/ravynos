#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "LibXml2::LibXml2" for configuration "Release"
set_property(TARGET LibXml2::LibXml2 APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(LibXml2::LibXml2 PROPERTIES
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libxml2.2.12.4.dylib"
  IMPORTED_SONAME_RELEASE "/usr/lib/libxml2.2.dylib"
  )

list(APPEND _cmake_import_check_targets LibXml2::LibXml2 )
list(APPEND _cmake_import_check_files_for_LibXml2::LibXml2 "${_IMPORT_PREFIX}/lib/libxml2.2.12.4.dylib" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
