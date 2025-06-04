#!/bin/bash

# Script to download the latest assets for specified applications from GitHub releases.
# Requires curl and jq to be installed.

set -e # Exit immediately if a command exits with a non-zero status.

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

TOOLS_DIR="$SCRIPT_DIR/tools"
mkdir -p "$TOOLS_DIR"

# --- Helper Functions ---

# Check if required commands exist
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: Required command '$1' is not installed." >&2
        echo "Please install '$1' and try again." >&2
        exit 1
    fi
}

# Download a file from a URL to a destination path
download_file() {
    local url="$1"
    local dest_path="$2"
    echo "   Attempting to download $url to $dest_path"
    # Use curl: -L follows redirects, -o specifies output file, -f fails silently on server errors, -S shows errors
    if curl -L -o "$dest_path" -fsS "$url"; then
        echo "   Downloaded: $dest_path"
        return 0 # Success
    else
        echo "   Error: Failed to download $url (curl exit code: $?)" >&2
        # Remove partially downloaded file on error
        rm -f "$dest_path"
        return 1 # Failure
    fi
}

# Download latest version from Maven Central by groupId, artifactId, and save as
download_latest_maven_jar() {
    local group_id="$1"
    local artifact_id="$2"
    local dest_path="$3"
    echo "   Fetching latest version for $artifact_id from Maven Central..."
    local group_url="${group_id//./\/}"
    local metadata_url="https://repo1.maven.org/maven2/$group_url/$artifact_id/maven-metadata.xml"
    local latest_version
    latest_version=$(curl -fsSL "$metadata_url" | grep -oPm1 "(?<=<latest>)[^<]+")
    if [ -z "$latest_version" ]; then
        # fallback to <release> if <latest> is not present
        latest_version=$(curl -fsSL "$metadata_url" | grep -oPm1 "(?<=<release>)[^<]+")
    fi
    if [ -z "$latest_version" ]; then
        echo "   Error: Could not determine latest version for $artifact_id" >&2
        return 1
    fi
    local jar_url="https://repo1.maven.org/maven2/$group_url/$artifact_id/$latest_version/$artifact_id-$latest_version.jar"
    download_file "$jar_url" "$dest_path"
}

# Download a jar from the latest GitHub release matching a pattern
download_github_jar() {
    local repo="$1"
    local jar_pattern="$2"
    local dest_path="$3"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    echo "   Fetching latest release from $repo..."
    local asset_url
    asset_url=$(curl -fsSL "$api_url" | jq -r --arg pattern "$jar_pattern" '
        .assets[] | select(.name | test($pattern)) | .browser_download_url' | head -n 1)
    if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
        echo "   Error: Asset matching pattern '$jar_pattern' not found in latest release of $repo" >&2
        return 1
    fi
    download_file "$asset_url" "$dest_path"
}

# --- Application Specific Download Functions ---

download_trc() {
    echo "Starting TinyRemapper CLI (trc) download..."
    download_github_jar "threadmc/tinyremapper-cli" "tinyremapper-cli-.*\.jar" "$TOOLS_DIR/trc.jar"
}

download_jopt_simple() {
    echo "Starting jopt-simple download..."
    download_latest_maven_jar "net.sf.jopt-simple" "jopt-simple" "$TOOLS_DIR/jopt-simple.jar"
}

download_asm() {
    echo "Starting ASM downloads..."
    download_latest_maven_jar "org.ow2.asm" "asm" "$TOOLS_DIR/asm.jar"
    download_latest_maven_jar "org.ow2.asm" "asm-commons" "$TOOLS_DIR/asm-commons.jar"
    download_latest_maven_jar "org.ow2.asm" "asm-util" "$TOOLS_DIR/asm-util.jar"
    download_latest_maven_jar "org.ow2.asm" "asm-tree" "$TOOLS_DIR/asm-tree.jar"
}

download_guava() {
    echo "Starting Guava download..."
    download_latest_maven_jar "com.google.guava" "guava" "$TOOLS_DIR/guava.jar"
}

download_vineflower() {
    echo "Starting Vineflower download..."
    download_latest_maven_jar "org.vineflower" "vineflower" "$TOOLS_DIR/vineflower.jar"
}

download_all() {
    download_vineflower
    download_trc
    download_jopt_simple
    download_asm
    download_guava
}

# --- Main Script ---

# Check for required argument
if [ -z "$1" ]; then
    echo "Usage: $0 <application_name>"
    echo "Example: $0 vineflower"
    echo "Available applications: vineflower, trc, jopt-simple, asm, guava, all"
    exit 1
fi

APP_TO_INSTALL="$1"

# Check common dependencies
check_command "curl"
check_command "jq"

# Execute download based on argument
case "$APP_TO_INSTALL" in
    vineflower)
        download_vineflower
        ;;
    trc)
        download_trc
        ;;
    jopt-simple)
        download_jopt_simple
        ;;
    asm)
        download_asm
        ;;
    guava)
        download_guava
        ;;
    all)
        download_all
        ;;
    *)
        echo "Error: Unknown application '$APP_TO_INSTALL'." >&2
        echo "Available applications: cfr, trc, jopt-simple, asm, guava, all"
        exit 1
        ;;
esac

# The exit status of the script will be the exit status of the called function
exit $?