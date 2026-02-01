#add_executable(objcdt STATIC
#	./runtime/objc-cache.mm
#	./objcdt/json.mm
#	./objcdt/objcdt.mm
#	./runtime/objc-probes.d
#)

add_library(objc SHARED
	./runtime/hashtable2.mm
	./runtime/maptable.mm
	./runtime/objc-auto.mm
	./runtime/objc-cache.mm
	./runtime/objc-class-old.mm
	./runtime/objc-class.mm
	./runtime/objc-errors.mm
	./runtime/objc-exception.mm
	./runtime/objc-file.mm
	./runtime/objc-initialize.mm
	./runtime/objc-layout.mm
	./runtime/objc-load.mm
	./runtime/objc-loadmethod.mm
	./runtime/objc-lockdebug.mm
	./runtime/objc-runtime-new.mm
	./runtime/objc-runtime-old.mm
	./runtime/objc-runtime.mm
	./runtime/objc-sel-set.mm
	./runtime/objc-sel.mm
	./runtime/objc-sync.mm
	./runtime/objc-typeencoding.mm
	./runtime/Object.mm
	./runtime/Protocol.mm
	./runtime/OldClasses.subproj/List.m
	./runtime/Messengers.subproj/objc-msg-x86_64.s
	./runtime/objc-accessors.mm
	./runtime/objc-references.mm
	./runtime/objc-os.mm
	./runtime/objc-file-old.mm
	./runtime/objc-block-trampolines.mm
	./runtime/objc-sel-table.s
	./runtime/objc-weak.mm
	./runtime/NSObject.mm
	./runtime/objc-opt.mm
	./runtime/objc-zalloc.mm
	./runtime/objc-cache-old.mm
	./runtime/objc-sel-old.mm

	./runtime/objc-probes.d # FIXME: need to generate .h from this
)
set_target_properties(objc PROPERTIES
    OUTPUT_NAME "objc.A" SUFFIX ".dylib" PREFIX "lib" NO_SONAME true)
set_source_files_properties(./runtime/objc-auto.mm TARGET_DIRECTORY objc PROPERTIES COMPILE_OPTIONS "-fexceptions")
set_source_files_properties(./runtime/objc-exception.mm TARGET_DIRECTORY objc PROPERTIES COMPILE_OPTIONS "-fexceptions")
set_source_files_properties(./runtime/objc-lockdebug.mm TARGET_DIRECTORY objc PROPERTIES COMPILE_OPTIONS "-Os")

target_compile_options(objc PRIVATE --sysroot=${RAVYN_SDKROOT}
    $<$<COMPILE_LANGUAGE:OBJC>:-std=gnu11>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-std=gnu++14>
    -mmacos-version-min=10.15 -fdollars-in-identifiers
    -fno-objc-convert-messages-to-runtime-calls
    -Wno-deprecated-declarations)

target_link_options(objc PRIVATE -Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib
    -L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/local/lib
    -Wl,-install_name,/usr/lib/libobjc.dylib -Wl,-current_version,228
    -Wl,-compatibility_version,1 -Wl,-order_file,${CMAKE_CURRENT_SOURCE_DIR}/libobjc.order
    -Wl,-interposable_list,${CMAKE_CURRENT_SOURCE_DIR}/interposable.txt
    -Wl,-sectalign,__DATA,0x1000 -lc++abi -lCrashReporterClient
    -Wl,-unexported_symbols,${CMAKE_CURRENT_SOURCE_DIR}/unexported_symbols
)
target_include_directories(objc PRIVATE runtime
    ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
    ${CMAKE_CURRENT_BINARY_DIR}/../Libsystem/libsystem_kernel/mig_hdr/include
    ../Libsystem/private ${RAVYN_SDKROOT}/usr/local/include
    ${RAVYN_SDKROOT}/usr/local/include/kernel
)

# SUPPORT_PREOPT and __OBJC2__ add support for the dyld objc shared cache
target_compile_definitions(objc PRIVATE
    TARGET_OS_IOSMAC=0 TARGET_OS_OSX=1 NDEBUG __OBJC2__ SUPPORT_PREOPT)

add_library(objc-trampolines SHARED
	./runtime/objc-blocktramps-i386.s
	./runtime/objc-blocktramps-x86_64.s
)
set_target_properties(objc-trampolines PROPERTIES
    OUTPUT_NAME "objc-trampolines" SUFFIX ".dylib" PREFIX "lib" NO_SONAME true)

add_dependencies(objc-trampolines libSystem)
add_dependencies(objc libSystem)