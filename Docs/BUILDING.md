# Building ravynOS From Source

## What you need:
* A host machine with:
  * clang 16.x+
  * cmake 3.15+ and ninja
  * GNU make (gmake)
  * BSD make (bmake)
  * zsh
  * Python 3
  * libpng (for xcbuild)

__NOTE:__ ravynOS currently only builds on macOS!

__On macOS:__
* Have a recent Xcode installed
* If your SDKs are not in the default place inside Xcode.app, export SDKROOT=/path/to/MacOSX.sdk before running build.sh

__On all platforms:__
Set your object directory if you don't want to use _/usr/obj/ravynOS/${ARCH}_: `export OBJTOP=/path/to/build_output_dir` or pass it on the command line below.

Run `./tools/build.sh kernel base`

## Subtle changes from previous branches:
* Versioning is now in Library/SystemVersion.plist.in, not version.txt
* The guts of the entire build process has been changed
