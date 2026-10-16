#!/bin/sh
set -eu
baseline213_root="<evidence-root>"
export CI=true BOT=true FLUTTER_SUPPRESS_ANALYTICS=true
unset FLUTTER_HOST FLUTTER_ANALYTICS_LOG_FILE
export FLUTTER_ROOT="$baseline213_root/tools/flutter"
export PUB_CACHE="$baseline213_root/state/pub-cache"
export GRADLE_USER_HOME="$baseline213_root/state/gradle"
export RUSTUP_HOME="$baseline213_root/state/rustup"
export CARGO_HOME="$baseline213_root/state/cargo"
export RUSTUP_TOOLCHAIN=1.97.1 RUSTUP_AUTO_INSTALL=0
export XDG_CONFIG_HOME="$baseline213_root/state/xdg-config"
export XDG_CACHE_HOME="$baseline213_root/state/xdg-cache"
export XDG_DATA_HOME="$baseline213_root/state/xdg-data"
export GEM_HOME="$baseline213_root/state/gems"
export GEM_PATH="$baseline213_root/state/gems"
export GEM_SPEC_CACHE="$baseline213_root/state/gem-spec-cache"
export GEMRC=/dev/null
export BUNDLE_USER_HOME="$baseline213_root/state/bundle"
export CP_HOME_DIR="$baseline213_root/state/cocoapods"
export CP_CACHE_DIR="$baseline213_root/state/cocoapods-cache"
export COCOAPODS_DISABLE_STATS=true
export ANDROID_USER_HOME="$baseline213_root/state/android-user"
unset ANDROID_PREFS_ROOT
export ANDROID_AVD_HOME="$baseline213_root/state/avd"
export ANDROID_EMULATOR_HOME="$baseline213_root/state/android-user"
unset ANDROID_SDK_HOME
export ANDROID_HOME="$baseline213_root/tools/android-sdk"
export ANDROID_SDK_ROOT="$baseline213_root/tools/android-sdk"
export ANDROID_NDK_HOME="$baseline213_root/tools/android-sdk/ndk/28.2.13676358"
export ANDROID_NDK_ROOT="$baseline213_root/tools/android-sdk/ndk/28.2.13676358"
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5042
export ANDROID_ADB_SERVER_PORT=5042
export JAVA_HOME="<user-home>/.local/share/mise/installs/java/zulu-17.66.19.0"
unset JAVA_OPTS GRADLE_OPTS
export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$baseline213_root/state/tmp -Djava.util.prefs.userRoot=$baseline213_root/state/java-prefs -Djava.util.prefs.systemRoot=$baseline213_root/state/java-system-prefs"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TMPDIR="$baseline213_root/state/tmp/"
export PATH="$FLUTTER_ROOT/bin:$baseline213_root/tools/pod-frozen:$baseline213_root/tools/gem-bin:<user-home>/.local/share/mise/installs/ruby/3.3.12/bin:$RUSTUP_HOME/toolchains/1.97.1-aarch64-apple-darwin/bin:<user-home>/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
exec "$@"
