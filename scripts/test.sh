#!/bin/zsh
# Runs the unit tests with Command Line Tools only (no Xcode): points the compiler at the bundled
# Swift Testing framework and skips the Testing/Foundation cross-import overlay, which CLT doesn't ship.
set -euo pipefail
cd "${0:A:h}/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F "$@"
