#!/bin/bash

# Script to download the latest assets for specified applications from GitHub releases.
# Requires curl and jq to be installed.

set -e # Exit immediately if a command exits with a non-zero status.

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

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

# --- Application Specific Download Functions ---

download_forgeflower() {
    echo "Starting ForgeFlower download..."
    # Define constants for ForgeFlower Maven
    local FORGE_MAVEN_BASE_URL="https://maven.minecraftforge.net/net/minecraftforge/forgeflower"
    local LATEST_VERSION_URL="$FORGE_MAVEN_BASE_URL/latest"
    local DESTINATION_FOLDER="$SCRIPT_DIR/dependencies/forgeflower" # Specific subfolder
    local SAVE_AS="forgeflower.jar"

    echo "Creating destination folder (if it doesn't exist): $DESTINATION_FOLDER"
    mkdir -p "$DESTINATION_FOLDER"

    echo "Fetching latest version string from: $LATEST_VERSION_URL"
    local latest_version
    latest_version=$(curl -fsSL "$LATEST_VERSION_URL")
    if [ $? -ne 0 ] || [ -z "$latest_version" ]; then
        echo "Error: Failed to fetch latest version string from $LATEST_VERSION_URL." >&2
        return 1
    fi
    # Trim potential whitespace/newlines
    latest_version=$(echo "$latest_version" | tr -d '[:space:]')
    if [ -z "$latest_version" ]; then
        echo "Error: Fetched version string is empty." >&2
        return 1
    fi

    echo "Latest ForgeFlower version found: $latest_version"

    # Construct the download URL
    local jar_filename="forgeflower-$latest_version.jar"
    local download_url="$FORGE_MAVEN_BASE_URL/$latest_version/$jar_filename"
    local dest_path="$DESTINATION_FOLDER/$SAVE_AS"

    echo "Attempting to download ForgeFlower JAR..."
    if download_file "$download_url" "$dest_path"; then
        echo "ForgeFlower download process finished successfully."
        return 0
    else
        echo "Error: Failed to download ForgeFlower JAR from $download_url" >&2
        return 1
    fi
}

# --- Main Script ---

# Check for required argument
if [ -z "$1" ]; then
    echo "Usage: $0 <application_name>"
    echo "Example: $0 forgeflower"
    # Add more examples here as you add applications
    exit 1
fi

APP_TO_INSTALL="$1"

# Check common dependencies
check_command "curl"
check_command "jq"

# Execute download based on argument
case "$APP_TO_INSTALL" in
    forgeflower)
        download_forgeflower
        ;;
    # Add more applications here like:
    # vineflower)
    #    download_vineflower
    #    ;;
    *)
        echo "Error: Unknown application '$APP_TO_INSTALL'." >&2
        echo "Available applications: forgeflower" # Update this list as you add more
        exit 1
        ;;
esac

# The exit status of the script will be the exit status of the called function
exit $?