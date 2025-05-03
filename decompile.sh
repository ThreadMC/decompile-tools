#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <minecraft_version> <output_directory>"
  exit 1
fi

VERSION=$1
OUT_DIR=$2

case "$OUT_DIR" in
  */) ;;
  *) OUT_DIR="${OUT_DIR}/" ;;
esac

FILE_PATH="./server-jars/versions/${VERSION}/server.jar"
FORGEFLOWER_PATH="./dependencies/forgeflower/forgeflower.jar"

if [ -f "$FILE_PATH" ]; then
  echo "Found server.jar at: $FILE_PATH"

  if [ ! -f "$FORGEFLOWER_PATH" ]; then
    echo "Error: ForgeFlower not found at $FORGEFLOWER_PATH"
    exit 1
  fi

  echo "Decompiling $FILE_PATH to $OUT_DIR using ForgeFlower..."
  java -jar "$FORGEFLOWER_PATH" "$FILE_PATH" "$OUT_DIR"

  if [ $? -eq 0 ]; then
    echo "Decompilation successful."
  else
    echo "Error: Decompilation failed."
    exit 1
  fi
else
  echo "Error: server.jar not found for version $VERSION at $FILE_PATH"
  exit 1
fi

exit 0