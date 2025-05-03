#!/bin/bash
set -e

# === Script directory ===
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# === Functions ===
error_exit() {
  echo "[-] $1"
  exit 1
}

info() {
  echo "[+] $1"
}

# === Tools ===
CFR_JAR="$SCRIPT_DIR/tools/cfr.jar"
SPECIALSOURCE_JAR="$SCRIPT_DIR/tools/specialsource.jar"
JOPT_SIMPLE_JAR="$SCRIPT_DIR/tools/jopt-simple.jar"
ASM_JAR="$SCRIPT_DIR/tools/asm.jar"
ASM_COMMONS_JAR="$SCRIPT_DIR/tools/asm-commons.jar"
ASM_UTILS_JAR="$SCRIPT_DIR/tools/asm-util.jar"
ASM_TREE_JAR="$SCRIPT_DIR/tools/asm-tree.jar"
GUAVA_JAR="$SCRIPT_DIR/tools/guava.jar"

# === Check for required tools ===
[ -f "$CFR_JAR" ] || error_exit "CFR Decompiler not found: $CFR_JAR"
[ -f "$SPECIALSOURCE_JAR" ] || error_exit "SpecialSource not found: $SPECIALSOURCE_JAR"
[ -f "$JOPT_SIMPLE_JAR" ] || error_exit "jopt-simple not found: $JOPT_SIMPLE_JAR"
[ -f "$ASM_JAR" ] || error_exit "ASM not found: $ASM_JAR"
[ -f "$ASM_COMMONS_JAR" ] || error_exit "ASM Commons not found: $ASM_COMMONS_JAR"
[ -f "$ASM_UTILS_JAR" ] || error_exit "ASM Utils not found: $ASM_UTILS_JAR"
[ -f "$ASM_TREE_JAR" ] || error_exit "ASM Tree not found: $ASM_TREE_JAR"
command -v jq >/dev/null 2>&1 || error_exit "'jq' is required but not installed. Please install jq."

# === Check argument ===
if [ -z "$1" ]; then
  echo "[!] Usage: $0 <mc_version> [workdir]"
  echo "Example: $0 1.21.5 ../minecraft-src-1.21.5"
  exit 1
fi
MC_VERSION="$1"
if [ -n "$2" ]; then
  WORKDIR="$2"
else
  WORKDIR="../minecraft-src-$MC_VERSION"
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# === Find server .jar URL ===
info "Searching for server jar for version ${MC_VERSION}..."
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"
VERSION_URL=$(curl -s "$MANIFEST_URL" | jq -r --arg VER "$MC_VERSION" '.versions[] | select(.id == $VER) | .url')
[ -z "$VERSION_URL" ] && error_exit "Version ${MC_VERSION} not found!"

SERVER_JAR_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.server.url // empty')
[ -z "$SERVER_JAR_URL" ] && error_exit "No server jar found for ${MC_VERSION}!"

info "Downloading Minecraft ${MC_VERSION} server jar..."
curl -o server.jar "$SERVER_JAR_URL"

# === Detect bundler presence ===
info "Checking if server jar contains Bundler (net.minecraft.bundler.Main)..."
if unzip -l server.jar | grep -q "net/minecraft/bundler/Main.class"; then
  HAS_BUNDLER=true
else
  HAS_BUNDLER=false
fi

# === Unpack (if Bundler present) or use server.jar directly ===
if [ "$HAS_BUNDLER" = true ]; then
  info "Bundler detected. Unpacking server libraries..."
  java -cp server.jar net.minecraft.bundler.Main

  SERVER_VERSION_JAR=$(find versions -name "*.jar" | head -n 1)
  [ -z "$SERVER_VERSION_JAR" ] && error_exit "Could not find unpacked server jar!"
else
  info "Bundler NOT detected. Using server.jar directly."
  SERVER_VERSION_JAR="server.jar"
fi

# === Download mappings ===
info "Downloading Mojang official mappings..."
MAPPINGS_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.client_mappings.url // empty')
[ -z "$MAPPINGS_URL" ] && error_exit "Mappings for ${MC_VERSION} not found!"

curl -o mappings.txt "$MAPPINGS_URL"

# === Apply mappings ===
info "Applying mappings (via SpecialSource)..."
mkdir -p build
java -cp "$SPECIALSOURCE_JAR:$JOPT_SIMPLE_JAR:$ASM_JAR:$ASM_COMMONS_JAR:$ASM_UTILS_JAR:$ASM_TREE_JAR:$GUAVA_JAR" net.md_5.specialsource.SpecialSource \
  -i "$SERVER_VERSION_JAR" \
  -m mappings.txt \
  -o build/server-mapped.jar

# === Decompile ===
info "Decompiling mapped jar (via CFR)..."
mkdir -p sources
java -jar "$CFR_JAR" build/server-mapped.jar --outputdir sources --caseinsensitivefs true --silent true

echo "[✓] Done! Decompiled sources in: $(realpath sources)"