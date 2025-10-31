What you need:
* a host machine with:
  * clang 16.x
  * cmake and ninja
  * GNU make (gmake)
  * BSD make (bmake)

On macOS:
* Have recent Xcode installed
* export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
* export OBJTOP=/path/to/build_output_dir
* ./tools/build.sh base
