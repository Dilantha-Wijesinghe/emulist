#!/bin/zsh
# Runs the unit tests. With Xcode this is plain `swift test`. With Command Line Tools only, it points the
# compiler at the bundled Swift Testing framework and skips the Testing/Foundation cross-import overlay,
# which CLT doesn't ship.
set -euo pipefail
cd "${0:A:h}/.."
developer="$(xcode-select -p)"
if [[ "$developer" == */CommandLineTools ]]; then
  F="$developer/Library/Developer/Frameworks"
  swift test -Xswiftc -F -Xswiftc $F -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F "$@"
else
  swift test "$@"
fi
