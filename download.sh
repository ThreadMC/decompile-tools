#!/bin/bash

# Script to download the latest assets for specified applications from GitHub releases or Maven Central.
# Requires curl to be installed.

set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

TOOLS_DIR="$SCRIPT_DIR/tools"
mkdir -p "$TOOLS_DIR"

# --- Helper Functions ---

# Check if required commands exist
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: Required command '$1' is not installed." >&2
        exit 1
    fi
}

# Download a file from a URL to a destination path
download_file() {
    local url="$1"
    local dest_path="$2"
    echo "Downloading $url to $dest_path"
    # Use curl: -L follows redirects, -o specifies output file, -f fails silently on server errors, -S shows errors
    if curl -L -o "$dest_path" -fsS "$url"; then
        return 0 # Success
    else
        echo "Error: Failed to download $url" >&2
        # Remove partially downloaded file on error
        rm -f "$dest_path"
        return 1 # Failure
    fi
}

# Get latest version from Maven Central by groupId, artifactId
get_latest_maven_version() {
    local group_id="$1"
    local artifact_id="$2"
    local group_url="${group_id//./\/}"
    local metadata_url="https://repo1.maven.org/maven2/$group_url/$artifact_id/maven-metadata.xml"
    local latest_version
    latest_version=$(curl -fsSL "$metadata_url" | grep -oPm1 "(?<=<latest>)[^<]+")
    if [ -z "$latest_version" ]; then
        # fallback to <release> if <latest> is not present
        latest_version=$(curl -fsSL "$metadata_url" | grep -oPm1 "(?<=<release>)[^<]+")
    fi
    if [ -z "$latest_version" ]; then
        echo "Failed to retrieve metadata for ${group_id}:${artifact_id}" >&2
        return 1
    fi
    echo "$latest_version"
}

# Download latest version from Maven Central by groupId, artifactId, and save as
download_maven_jar() {
    local group_id="$1"
    local artifact_id="$2"
    local dest_path="$3"
    local version
    version=$(get_latest_maven_version "$group_id" "$artifact_id") || { echo "Could not determine latest version for ${artifact_id}" >&2; return 1; }
    local group_url="${group_id//./\/}"
    local jar_url="https://repo1.maven.org/maven2/$group_url/$artifact_id/$version/$artifact_id-$version.jar"
    download_file "$jar_url" "$dest_path"
}

# Download latest jar from GitHub releases by repository and jar pattern
download_github_jar() {
    local repo="$1"
    local jar_pattern="$2"
    local dest_path="$3"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local asset_url
    asset_url=$(curl -fsSL "$api_url" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -E "$jar_pattern" | head -n1)
    if [ -z "$asset_url" ]; then
        echo "Asset matching pattern '${jar_pattern}' not found in latest release of ${repo}" >&2
        return 1
    fi
    download_file "$asset_url" "$dest_path"
}

# --- Application Specific Download Functions ---

download_vineflower() {
    echo "Starting Vineflower download..."
    download_maven_jar "org.vineflower" "vineflower" "$TOOLS_DIR/vineflower.jar"
}

download_specialsource() {
    echo "Starting SpecialSource download..."
    download_maven_jar "net.md-5" "SpecialSource" "$TOOLS_DIR/specialsource.jar"
}

download_trc() {
    echo "Starting TRC download..."
    download_github_jar "threadmc/trc" "trc-.*\.jar" "$TOOLS_DIR/trc.jar"
}

download_jopt_simple() {
    echo "Starting jopt-simple download..."
    download_maven_jar "net.sf.jopt-simple" "jopt-simple" "$TOOLS_DIR/jopt-simple.jar"
}

download_asm() {
    echo "Starting ASM downloads..."
    download_maven_jar "org.ow2.asm" "asm" "$TOOLS_DIR/asm.jar"
    download_maven_jar "org.ow2.asm" "asm-commons" "$TOOLS_DIR/asm-commons.jar"
    download_maven_jar "org.ow2.asm" "asm-util" "$TOOLS_DIR/asm-util.jar"
    download_maven_jar "org.ow2.asm" "asm-tree" "$TOOLS_DIR/asm-tree.jar"
}

download_guava() {
    echo "Starting Guava download..."
    download_maven_jar "com.google.guava" "guava" "$TOOLS_DIR/guava.jar"
}

download_all() {
    download_vineflower
    download_specialsource
    download_trc
    download_jopt_simple
    download_asm
    download_guava
}

# --- Main Script ---

# Check for required argument
if [ -z "$1" ]; then
    echo "Usage: $0 <application_name>"
    echo "Available applications: vineflower, specialsource, trc, jopt-simple, asm, guava, all"
    exit 1
fi

APP_TO_INSTALL="$1"

# Check common dependencies
check_command "curl"

# Execute download based on argument
case "$APP_TO_INSTALL" in
    vineflower)
        download_vineflower
        ;;
    specialsource)
        download_specialsource
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
        echo "Available applications: vineflower, specialsource, trc, jopt-simple, asm, guava, all"
        exit 1
        ;;
esac

# The exit status of the script will be the exit status of the called function
exit $?