#!/usr/bin/env bash
#
# Build the Java/Android portion of btleplug (src/droidplug/java).
#
# Checks for and installs Java (via Homebrew on macOS) if necessary,
# locates the Android SDK, then runs the Gradle build.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAVA_DIR="$PROJECT_ROOT/src/droidplug/java"

# --- Colors (if terminal) ---------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

# --- Detect OS ---------------------------------------------------------------
OS="$(uname -s)"

# --- Java --------------------------------------------------------------------
ensure_java() {
    if command -v java &>/dev/null && java -version &>/dev/null 2>&1; then
        local ver
        ver="$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
        if [ "$ver" -ge 11 ] 2>/dev/null; then
            info "Java $ver found: $(command -v java)"
            return 0
        else
            warn "Java $ver found but AGP 7.4 requires Java >= 11"
        fi
    fi

    info "Java not found or too old — attempting to install..."

    case "$OS" in
        Darwin)
            if ! command -v brew &>/dev/null; then
                die "Homebrew not found. Install it from https://brew.sh or install Java 11+ manually."
            fi
            info "Installing openjdk@17 via Homebrew..."
            brew install openjdk@17
            # Homebrew installs openjdk to its prefix; create the system symlink
            # so /usr/libexec/java_home can find it. This may fail without sudo
            # but we can still use it directly via JAVA_HOME.
            local jdk_path
            jdk_path="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
            if [ -d "$jdk_path" ]; then
                export JAVA_HOME="$jdk_path"
                export PATH="$JAVA_HOME/bin:$PATH"
            else
                die "openjdk@17 installed but JDK home not found at expected path."
            fi
            ;;
        Linux)
            if command -v apt-get &>/dev/null; then
                info "Installing openjdk-17-jdk via apt..."
                sudo apt-get update -qq && sudo apt-get install -y -qq openjdk-17-jdk
            elif command -v dnf &>/dev/null; then
                info "Installing java-17-openjdk-devel via dnf..."
                sudo dnf install -y java-17-openjdk-devel
            elif command -v pacman &>/dev/null; then
                info "Installing jdk17-openjdk via pacman..."
                sudo pacman -S --noconfirm jdk17-openjdk
            else
                die "Could not detect package manager. Install Java 11+ manually."
            fi
            ;;
        *)
            die "Unsupported OS '$OS'. Install Java 11+ manually."
            ;;
    esac

    # Verify
    if ! command -v java &>/dev/null || ! java -version &>/dev/null 2>&1; then
        die "Java installation failed or 'java' is not on PATH."
    fi
    info "Java installed successfully."
}

# --- JAVA_HOME ---------------------------------------------------------------
ensure_java_home() {
    if [ -n "${JAVA_HOME:-}" ] && [ -d "$JAVA_HOME" ]; then
        return 0
    fi

    case "$OS" in
        Darwin)
            JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
            # Fallback: check Homebrew openjdk directly
            if [ -z "${JAVA_HOME:-}" ] || [ ! -d "${JAVA_HOME:-}" ]; then
                for v in 17 21 11; do
                    local brew_jdk
                    brew_jdk="$(brew --prefix "openjdk@$v" 2>/dev/null || true)"
                    if [ -n "$brew_jdk" ] && [ -d "$brew_jdk/libexec/openjdk.jdk/Contents/Home" ]; then
                        JAVA_HOME="$brew_jdk/libexec/openjdk.jdk/Contents/Home"
                        break
                    fi
                done
            fi
            ;;
        Linux)
            # Common locations
            for candidate in \
                /usr/lib/jvm/java-17-openjdk-amd64 \
                /usr/lib/jvm/java-17-openjdk \
                /usr/lib/jvm/java-17 \
                /usr/lib/jvm/default-java; do
                if [ -d "$candidate" ]; then
                    JAVA_HOME="$candidate"
                    break
                fi
            done
            ;;
    esac

    if [ -z "${JAVA_HOME:-}" ]; then
        die "Could not determine JAVA_HOME. Set it manually and re-run."
    fi
    export JAVA_HOME
    info "JAVA_HOME=$JAVA_HOME"
}

# --- Android SDK -------------------------------------------------------------
ensure_android_sdk() {
    if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
        info "ANDROID_HOME=$ANDROID_HOME"
        return 0
    fi

    # Check ANDROID_SDK_ROOT (older env var)
    if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
        export ANDROID_HOME="$ANDROID_SDK_ROOT"
        info "ANDROID_HOME=$ANDROID_HOME (from ANDROID_SDK_ROOT)"
        return 0
    fi

    # Common default locations
    local candidates=()
    case "$OS" in
        Darwin) candidates=("$HOME/Library/Android/sdk") ;;
        Linux)  candidates=("$HOME/Android/Sdk" "$HOME/android-sdk") ;;
    esac

    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate" ]; then
            export ANDROID_HOME="$candidate"
            info "ANDROID_HOME=$ANDROID_HOME (auto-detected)"
            return 0
        fi
    done

    die "Android SDK not found. Set ANDROID_HOME and re-run, or install via Android Studio / sdkmanager."
}

# --- Write local.properties --------------------------------------------------
write_local_properties() {
    local props="$JAVA_DIR/local.properties"
    # Gradle Android plugin requires sdk.dir in local.properties
    echo "sdk.dir=$ANDROID_HOME" > "$props"
    info "Wrote $props"
}

# --- jni-utils SNAPSHOT dependency -------------------------------------------
JNI_UTILS_DIR="$PROJECT_ROOT/../jni-utils-rs"

build_jni_utils() {
    if [ ! -d "$JNI_UTILS_DIR/java" ]; then
        die "jni-utils-rs not found at $JNI_UTILS_DIR" \
            "Clone it with: git clone https://github.com/nickelc/jni-utils-rs $JNI_UTILS_DIR"
    fi

    local jni_java_dir
    jni_java_dir="$(cd "$JNI_UTILS_DIR/java" && pwd)"

    info "Building jni-utils Java library from $jni_java_dir ..."

    if [ ! -x "$jni_java_dir/gradlew" ]; then
        chmod +x "$jni_java_dir/gradlew"
    fi

    (cd "$jni_java_dir" && ./gradlew publishToMavenLocal -q)

    # Verify it landed
    local snapshot_dir="$HOME/.m2/repository/io/github/gedgygedgy/rust/jni-utils/0.1.1-SNAPSHOT"
    if [ ! -d "$snapshot_dir" ]; then
        die "jni-utils publishToMavenLocal succeeded but artifact not found in $snapshot_dir"
    fi
    info "jni-utils 0.1.1-SNAPSHOT published to mavenLocal."
}

# --- Build -------------------------------------------------------------------
run_gradle_build() {
    info "Running Gradle build in $JAVA_DIR ..."
    cd "$JAVA_DIR"

    if [ ! -x ./gradlew ]; then
        chmod +x ./gradlew
    fi

    ./gradlew assembleDebug assembleRelease "$@"

    info "Java build completed successfully."
}

# --- Main --------------------------------------------------------------------
main() {
    info "btleplug Java/Android build"
    echo

    ensure_java
    ensure_java_home
    ensure_android_sdk
    write_local_properties
    build_jni_utils
    echo
    run_gradle_build "$@"
}

main "$@"
