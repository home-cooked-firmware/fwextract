#!/usr/bin/env bash

# Usage:
# fwextract <path to firmware file> <name of extraction config>
#
# Example:
# fwextract RG35XX+-P-V1.1.6-EN16GB-240822.img anbernic-rg35xx-2024-plus

FWE_COMMAND=$1

# Loads a firmware extraction configuration.
#
# Params:
# 1. config id - ID of configuration to load.
#
# Example:
# ```
# load_config "anbernic-rg35xx-h"
# ```
load_config () {
  LOAD_CONFIG_ID="$1"
  # TODO Check that file exists before attempting to source it.
  source "/fwextract-configs/$LOAD_CONFIG_ID.env"
}

# Unloads a firmware extraction configuration.
#
# All relevant `FWEXTRACT_CONF_` variables are unset by this function.
unload_config () {
  FWEXTRACT_CONF_META_ID=""
  FWEXTRACT_CONF_META_NAME=""
  FWEXTRACT_CONF_BOOT0_OFFSET_KB=""
  FWEXTRACT_CONF_BOOT0_SIZE_KB=""
  FWEXTRACT_CONF_BOOTPACKAGE_OFFSET_KB=""
  FWEXTRACT_CONF_BOOTPACKAGE_SIZE_KB=""
}

# Fetches configs in configs dir and prints the list of configs (IDs and names).
list_configs () {
  for CONFIG_FILENAME in /fwextract-configs/*.env; do
    set -a
    source "$CONFIG_FILENAME"
    set +a

    echo "$FWEXTRACT_CONF_META_ID ($FWEXTRACT_CONF_META_NAME)"
  done
  unload_config
}

# Extracts firmware data from a file.
#
# Params:
# 1. input file path - Path to input file from which to extract data.
# 2. output file path - Path to output file.
# 3. block size - Extraction block size in bytes.
# 4. offset - Extraction offset using the given block size.
# 5. size - Extraction size using the given block size.
extract () {
  EXTRACT_INPUT_FILEPATH="$1"
  EXTRACT_OUTPUT_FILEPATH="$2"
  EXTRACT_BLOCK_SIZE="$3"
  EXTRACT_OFFSET="$4"
  EXTRACT_SIZE="$5"

  dd if="$EXTRACT_INPUT_FILEPATH" \
     of="$EXTRACT_OUTPUT_FILEPATH" \
     bs="$EXTRACT_BLOCK_SIZE" \
     skip="$EXTRACT_OFFSET" \
     count="$EXTRACT_SIZE"

  # TODO Save more info than just MD5 checksum.
  #      Include extraction date, name of file from which firmware was extracted, etc.
  EXTRACT_MD5_HASH=($(md5sum "$EXTRACT_OUTPUT_FILEPATH"))
  echo $EXTRACT_MD5_HASH > "$EXTRACT_OUTPUT_FILEPATH.md5"
}

# Prints the offset of a partition in the given image to stdout.
#
# Params:
# 1. input file path - Path to input image file from which to retrieve offset.
# 2. partition index - Partition number for which to retrieve offset.
get_partition_offset () {
  PARTITION_INPUT_FILE="$1"
  PARTITION_NUMBER="$2"
  PARTITION_DATA_REGEX="^\s*([0-9]+)\s+[0-9]+\s+([0-9]+)"

  # Run fdisk and get the row that corresponds to the desired partition index (`$2`).
  PARTITION_FDISK_ROW=$(fdisk -l "$PARTITION_INPUT_FILE" | grep "$PARTITION_INPUT_FILE$PARTITION_NUMBER")
  PARTITION_FDISK_DATA=${PARTITION_FDISK_ROW#"$PARTITION_INPUT_FILE$PARTITION_NUMBER"}

  if [[ $PARTITION_FDISK_DATA =~ $PARTITION_DATA_REGEX ]]
  then
    echo "${BASH_REMATCH[1]}"
  fi

  # TODO Handle failure.
}

# Prints the size of a partition in the given image to stdout.
#
# Params:
# 1. input file path - Path to input image file from which to retrieve size.
# 2. partition index - Partition number for which to retrieve size.
get_partition_size () {
  PARTITION_INPUT_FILE="$1"
  PARTITION_NUMBER="$2"
  PARTITION_DATA_REGEX="^\s*([0-9]+)\s+[0-9]+\s+([0-9]+)"

  # Run fdisk and get the row that corresponds to the desired partition index (`$2`).
  PARTITION_FDISK_ROW=$(fdisk -l "$PARTITION_INPUT_FILE" | grep "$PARTITION_INPUT_FILE$PARTITION_NUMBER")
  PARTITION_FDISK_DATA=${PARTITION_FDISK_ROW#"$PARTITION_INPUT_FILE$PARTITION_NUMBER"}

  if [[ $PARTITION_FDISK_DATA =~ $PARTITION_DATA_REGEX ]]
  then
    echo "${BASH_REMATCH[2]}"
  fi

  # TODO Handle failure.
}

# Deletes all files in the given directory.
#
# Params:
# 1. clean path - Path to directory to clean.
clean () {
  CLEAN_DIR_PATH="$1"
  echo "Cleaning $CLEAN_DIR_PATH..."
  rm -rf "$CLEAN_DIR_PATH"
}

case $FWE_COMMAND in
  # List known firmware configs.
  configs)
    list_configs
    ;;

  clean)
    clean "/fwextract-output"
    echo "Done"
    ;;

  # Extract firmware using a specified configuration.
  extract)
    INPUT_FILE="$2"
    INPUT_NAME="${INPUT_FILE%.*}"
    OUTPUT_DIR="/fwextract-output/${INPUT_NAME}"
    CONFIG_ID="$3"

    load_config "$CONFIG_ID"
    clean "$OUTPUT_DIR"
    mkdir "$OUTPUT_DIR"

    # Get partition offsets and sizes for `boot.img` and `env.img`.
    # TODO Use configuration values for partition indices.
    BOOT_IMG_OFFSET=$(get_partition_offset "/fwextract-input/$INPUT_FILE" "4")
    BOOT_IMG_SIZE=$(get_partition_size "/fwextract-input/$INPUT_FILE" "4")
    ENV_IMG_OFFSET=$(get_partition_offset "/fwextract-input/$INPUT_FILE" "3")
    ENV_IMG_SIZE=$(get_partition_size "/fwextract-input/$INPUT_FILE" "3")

    # Extract `boot0.img`.
    extract \
      "/fwextract-input/$INPUT_FILE" \
      "$OUTPUT_DIR/boot0.img" \
      "1024" \
      "$FWEXTRACT_CONF_BOOT0_OFFSET_KB" \
      "$FWEXTRACT_CONF_BOOT0_SIZE_KB"

    # Extract `boot_package.img`.
    extract \
      "/fwextract-input/$INPUT_FILE" \
      "$OUTPUT_DIR/boot_package.img" \
      "1024" \
      "$FWEXTRACT_CONF_BOOTPACKAGE_OFFSET_KB" \
      "$FWEXTRACT_CONF_BOOTPACKAGE_SIZE_KB"

    # Extract `boot.img`
    extract \
      "/fwextract-input/$INPUT_FILE" \
      "$OUTPUT_DIR/boot.img" \
      "512" \
      "$BOOT_IMG_OFFSET" \
      "$BOOT_IMG_SIZE"

    # Extract `env.img`
    extract \
      "/fwextract-input/$INPUT_FILE" \
      "$OUTPUT_DIR/env.img" \
      "512" \
      "$ENV_IMG_OFFSET" \
      "$ENV_IMG_SIZE"

    unload_config
    echo "Done"
    ;;
esac
