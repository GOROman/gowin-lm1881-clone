#!/bin/sh
# macOS 版 GOWIN EDA の gw_sh ラッパ (DYLD パスを通す)
GW=${GOWIN_HOME:-/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA}
export DYLD_FRAMEWORK_PATH="$GW/IDE/lib"
export DYLD_LIBRARY_PATH="$GW/IDE/lib"
exec "$GW/IDE/bin/gw_sh" "$@"
