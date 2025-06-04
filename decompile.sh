#!/bin/bash
set -e

# === Functions ===
error_exit() {
  echo "[-] $1" >&2
  exit 1
}

info() {
  echo "[+] $1"
}

# === Args ===
if [ -z "$1" ]; then
  echo "Usage: $0 <mc_version> [workdir] [mappingtype: mojang|fabric]"
  exit 1
fi
MC_VERSION="$1"
WORKDIR="${2:-../minecraft-src-$MC_VERSION}"
MAPPING_TYPE="${3:-mojang}"

# === Script directory ===
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TOOLS_DIR="$SCRIPT_DIR/tools"

# === Tools ===
SPECIALSOURCE_JAR="$TOOLS_DIR/specialsource.jar"
JOPT_SIMPLE_JAR="$TOOLS_DIR/jopt-simple.jar"
ASM_JAR="$TOOLS_DIR/asm.jar"
ASM_COMMONS_JAR="$TOOLS_DIR/asm-commons.jar"
ASM_UTILS_JAR="$TOOLS_DIR/asm-util.jar"
ASM_TREE_JAR="$TOOLS_DIR/asm-tree.jar"
GUAVA_JAR="$TOOLS_DIR/guava.jar"
VINEFLOWER_JAR="$TOOLS_DIR/vineflower.jar"
TRC_JAR="$TOOLS_DIR/trc.jar"

# === Check for required tools ===
for f in "$VINEFLOWER_JAR" "$SPECIALSOURCE_JAR" "$JOPT_SIMPLE_JAR" "$ASM_JAR" "$ASM_COMMONS_JAR" "$ASM_UTILS_JAR" "$ASM_TREE_JAR" "$GUAVA_JAR" "$TRC_JAR"; do
  [ -f "$f" ] || error_exit "Required tool not found: $f"
done
command -v jq >/dev/null 2>&1 || error_exit "'jq' is required but not installed. Please install jq."
command -v curl >/dev/null 2>&1 || error_exit "'curl' is required but not installed. Please install curl."
command -v unzip >/dev/null 2>&1 || error_exit "'unzip' is required but not installed. Please install unzip."

# === Prepare workdir ===
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# === Fetch version manifest ===
info "Fetching version manifest..."
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"
MANIFEST_JSON=$(curl -s "$MANIFEST_URL") || error_exit "Failed to retrieve version manifest."
VERSION_URL=$(echo "$MANIFEST_JSON" | jq -r --arg VER "$MC_VERSION" '.versions[] | select(.id == $VER) | .url')
[ -z "$VERSION_URL" ] && error_exit "Version $MC_VERSION not found in manifest."

VERSION_JSON=$(curl -s "$VERSION_URL") || error_exit "Failed to retrieve version data."

# === Download libraries ===
LIBRARIES_DIR="$WORKDIR/libraries"
mkdir -p "$LIBRARIES_DIR"
echo "$VERSION_JSON" | jq -c '.libraries[]?' | while read -r lib; do
  ARTIFACT_URL=$(echo "$lib" | jq -r '.downloads.artifact.url // empty')
  ARTIFACT_PATH=$(echo "$lib" | jq -r '.downloads.artifact.path // empty')
  LIB_NAME=$(echo "$lib" | jq -r '.name // empty')
  if [ -n "$ARTIFACT_URL" ] && [ -n "$ARTIFACT_PATH" ]; then
    LIB_PATH="$LIBRARIES_DIR/$ARTIFACT_PATH"
    LIB_DIR=$(dirname "$LIB_PATH")
    mkdir -p "$LIB_DIR"
    if [ ! -f "$LIB_PATH" ]; then
      info "Downloading library: $LIB_NAME"
      curl -f -L -o "$LIB_PATH" "$ARTIFACT_URL" || echo "Warning: Failed to download $LIB_NAME"
    fi
  fi
done

# === Download server jar ===
SERVER_JAR_URL=$(echo "$VERSION_JSON" | jq -r '.downloads.server.url // empty')
[ -z "$SERVER_JAR_URL" ] && error_exit "Server JAR URL not found for version $MC_VERSION."
info "Downloading server JAR..."
curl -f -L -o server.jar "$SERVER_JAR_URL"

# === Check for Bundler ===
info "Checking for Bundler..."
if unzip -l server.jar | grep -q "net/minecraft/bundler/Main.class"; then
  HAS_BUNDLER=true
else
  HAS_BUNDLER=false
fi

if [ "$HAS_BUNDLER" = true ]; then
  info "Bundler detected. Unpacking..."
  java -cp server.jar net.minecraft.bundler.Main
  SERVER_VERSION_JAR=$(find versions -name "*.jar" | head -n 1)
  [ -z "$SERVER_VERSION_JAR" ] && error_exit "Unpacked server JAR not found."
  SERVER_JAR_PATH="$SERVER_VERSION_JAR"
else
  info "No Bundler detected. Using server.jar directly."
  SERVER_JAR_PATH="server.jar"
fi

# === Strip META-INF ===
STRIPPED_JAR_PATH="$WORKDIR/server-stripped.jar"
info "Stripping META-INF from server jar to avoid signature issues..."
if [ -f "$STRIPPED_JAR_PATH" ]; then rm -f "$STRIPPED_JAR_PATH"; fi
zip -q -d "$SERVER_JAR_PATH" 'META-INF/*' || true
cp "$SERVER_JAR_PATH" "$STRIPPED_JAR_PATH"
SERVER_JAR_PATH="$STRIPPED_JAR_PATH"

# === Mapping logic ===
mkdir -p build

if [ "$MAPPING_TYPE" = "mojang" ]; then
  MAPPINGS_URL=$(echo "$VERSION_JSON" | jq -r '.downloads.server_mappings.url // empty')
  [ -z "$MAPPINGS_URL" ] && error_exit "Mappings URL not found for version $MC_VERSION."
  info "Downloading Mojang mappings..."
  curl -f -L -o mappings.txt "$MAPPINGS_URL"
  info "Applying Mojang mappings..."
  java -cp "$SPECIALSOURCE_JAR:$JOPT_SIMPLE_JAR:$ASM_JAR:$ASM_COMMONS_JAR:$ASM_UTILS_JAR:$ASM_TREE_JAR:$GUAVA_JAR" net.md_5.specialsource.SpecialSource \
    -i "$SERVER_JAR_PATH" \
    -m mappings.txt \
    -o build/server-mapped.jar

  MAPPED_JAR="build/server-mapped.jar"

elif [ "$MAPPING_TYPE" = "fabric" ]; then
  FABRIC_META_URL="https://meta.fabricmc.net/v2/versions/intermediary/$MC_VERSION"
  info "Fetching Fabric intermediary metadata..."
  FABRIC_META=$(curl -s "$FABRIC_META_URL") || error_exit "Failed to retrieve Fabric intermediary metadata."
  MAVEN_COORD=$(echo "$FABRIC_META" | jq -r '.[0].maven // empty')
  [ -z "$MAVEN_COORD" ] && error_exit "No Fabric intermediary found for version $MC_VERSION."
  IFS=':' read -r group artifact version <<< "$MAVEN_COORD"
  group_path=$(echo "$group" | tr . /)
  INTERMEDIARY_TINY_URL="https://maven.fabricmc.net/$group_path/$artifact/$version/$artifact-$version.tiny"
  INTERMEDIARY_JAR_URL="https://maven.fabricmc.net/$group_path/$artifact/$version/$artifact-$version.jar"
  TINY_PATH="$WORKDIR/intermediary.tiny"
  JAR_PATH="$WORKDIR/intermediary.jar"

  info "Attempting to download Fabric intermediary mappings (.tiny): $INTERMEDIARY_TINY_URL"
  if ! curl -f -L -o "$TINY_PATH" "$INTERMEDIARY_TINY_URL"; then
    info "Direct .tiny not found, downloading intermediary jar: $INTERMEDIARY_JAR_URL"
    curl -f -L -o "$JAR_PATH" "$INTERMEDIARY_JAR_URL"
    unzip -p "$JAR_PATH" "mappings/mappings.tiny" > "$TINY_PATH" || error_exit "mappings/mappings.tiny not found in intermediary jar."
    rm -f "$JAR_PATH"
    [ ! -s "$TINY_PATH" ] && error_exit "Failed to extract mappings.tiny from intermediary jar."
  fi

  info "Applying Fabric intermediary mappings with tiny-remapper..."
  java -jar "$TRC_JAR" \
    --input "$SERVER_JAR_PATH" \
    --output "build/server-mapped.jar" \
    --mappings "$TINY_PATH" \
    --from "official" \
    --to "intermediary"
  MAPPED_JAR="build/server-mapped.jar"

  # Try to download named mappings and apply if available
  NAMED_MAPPINGS_URL="https://maven.fabricmc.net/net/fabricmc/yarn/$MC_VERSION+build.1/yarn-$MC_VERSION+build.1-tiny.gz"
  NAMED_TINY_GZ_PATH="$WORKDIR/named.tiny.gz"
  NAMED_TINY_PATH="$WORKDIR/named.tiny"
  if curl -f -L -o "$NAMED_TINY_GZ_PATH" "$NAMED_MAPPINGS_URL"; then
    info "Decompressing Fabric named mappings .gz..."
    gunzip -c "$NAMED_TINY_GZ_PATH" > "$NAMED_TINY_PATH"
    rm -f "$NAMED_TINY_GZ_PATH"
    info "Applying Fabric named mappings with tiny-remapper..."
    java -jar "$TRC_JAR" \
      --input "$MAPPED_JAR" \
      --output "build/server-named.jar" \
      --mappings "$NAMED_TINY_PATH" \
      --from "intermediary" \
      --to "named"
    MAPPED_JAR="build/server-named.jar"
  else
    info "Fabric named mappings not found for this version, skipping named remap."
  fi

else
  error_exit "Unknown mapping type: $MAPPING_TYPE"
fi

# === Decompile ===
info "Decompiling with VineFlower..."
mkdir -p sources
java -jar "$VINEFLOWER_JAR" "$MAPPED_JAR" --outputdir sources

info "Decompilation complete. Sources located at: $(realpath sources)"