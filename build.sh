#!/bin/bash

set -e -o pipefail

ARM_TOOLCHAIN_VERSION=9.2-2019.12
ARM_TOOLCHAIN_FILENAME=gcc-arm-${ARM_TOOLCHAIN_VERSION}-x86_64-arm-none-eabi.tar.xz
ARM_TOOLCHAIN_URL=https://developer.arm.com/-/media/Files/downloads/gnu-a/${ARM_TOOLCHAIN_VERSION}/binrel/${ARM_TOOLCHAIN_FILENAME}
ARM_TOOLCHAIN_SHA256SUM=ac952d89ae0fc3543e81099e7d34917efc621f5def112eee843fd1ce755eca8c

AARCH64_TOOLCHAIN_VERSION=9.2-2019.12
AARCH64_TOOLCHAIN_FILENAME=gcc-arm-${AARCH64_TOOLCHAIN_VERSION}-x86_64-aarch64-none-elf.tar.xz
AARCH64_TOOLCHAIN_URL=https://developer.arm.com/-/media/Files/downloads/gnu-a/${AARCH64_TOOLCHAIN_VERSION}/binrel/${AARCH64_TOOLCHAIN_FILENAME}
AARCH64_TOOLCHAIN_SHA256SUM=36d2cbe7c2984f2c20f562ac2f3ba524c59151adfa8ee10f1326c88de337b6d1

ATF_SOURCE_VERSION=2.3-rc0
ATF_SOURCE_FILENAME=arm-trusted-firmware-v${ATF_SOURCE_VERSION}.tar.gz
ATF_SOURCE_URL=https://codeload.github.com/ARM-software/arm-trusted-firmware/tar.gz/v${ATF_SOURCE_VERSION}
ATF_SOURCE_SHA256SUM=d0f2c71462c43e5815f8d906558782f7c583e4c07cc972aa8a53124ca8b48886
# Set fixed build timestamp for reproducible builds
ATF_BUILD_EPOCH=1586976479

die() {
  echo "$@" 1>&2
  exit 1
}

download_and_check() {
  local URL="$1"
  local FILENAME="download_dir/$2"
  local SHA256SUM="$3"

  mkdir -p "download_dir"
  rm -f "$FILENAME"
  wget --retry-connrefused --waitretry=1 --read-timeout=20 \
    --timeout=15 -t 5 -O "$FILENAME" "$URL"
  shasum="$(sha256sum "$FILENAME" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')"
  if [[ "$shasum" == "$SHA256SUM"  ]]; then
    echo "$FILENAME"
    return 0
  fi
  rm -f "$FILENAME"
  die "Checksum missmatch on $FILENAME, $shasum != $SHA256SUM"
}

extract() {
  ARCHIVE="$1"

  rm -rf "${ARCHIVE}_extracted"
  mkdir -p "${ARCHIVE}_extracted"
  tar -C "${ARCHIVE}_extracted" -xaf "$ARCHIVE"
  realpath "${ARCHIVE}_extracted"/*
}

rm -rf download_dir

echo "Downloading ARM toolchain ..."
ARM_TOOLCHAIN_FILENAME="$(download_and_check "$ARM_TOOLCHAIN_URL" "$ARM_TOOLCHAIN_FILENAME" "$ARM_TOOLCHAIN_SHA256SUM")"
echo "Downloading AARCH64 toolchain ..."
AARCH64_TOOLCHAIN_FILENAME="$(download_and_check "$AARCH64_TOOLCHAIN_URL" "$AARCH64_TOOLCHAIN_FILENAME" "$AARCH64_TOOLCHAIN_SHA256SUM")"
echo "Downloading ATF source ..."
ATF_SOURCE_FILENAME="$(download_and_check "$ATF_SOURCE_URL" "$ATF_SOURCE_FILENAME" "$ATF_SOURCE_SHA256SUM")"

echo "Extracting ARM toolchain ..."
CROSS_COMPILE_ARM="$(extract "$ARM_TOOLCHAIN_FILENAME")"/bin/arm-none-eabi-
echo "Extracting AARCH64 toolchain ..."
CROSS_COMPILE_AARCH64="$(extract "$AARCH64_TOOLCHAIN_FILENAME")"/bin/aarch64-none-elf-

rm -rf output_dir
mkdir output_dir

for target in targets/*.sh; do
  # Unpack clean tree
  ATF_DIR="$(extract "$ATF_SOURCE_FILENAME")"

  unset PLAT TARGET BINARY_FORMAT ARCH MAKE_FLAGS
  . "$target"

  case "$ARCH" in
    aarch64) CROSS_COMPILE="$CROSS_COMPILE_AARCH64";;
    arm) CROSS_COMPILE="$CROSS_COMPILE_ARM";;
    *) die Invalid arch "$ARCH";;
  esac

  make -C "$ATF_DIR" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    M0_CROSS_COMPILE="$CROSS_COMPILE_ARM" \
    CROSS_CM3="$CROSS_COMPILE_ARM" \
    PLAT="$PLAT" \
    SOURCE_DATE_EPOCH="$ATF_BUILD_EPOCH" \
    $MAKE_FLAGS \
    "$TARGET"

  cp ${ATF_DIR}/build/${PLAT}/release/${TARGET}/${TARGET}.${BINARY_FORMAT} output_dir/${PLAT}_${TARGET}.${BINARY_FORMAT}
  rm -rf ${ATF_DIR}
done

cat << EOF > build_info.txt
build epoch: $ATF_BUILD_EPOCH

EOF
sha256sum download_dir/* 2> /dev/null >> build_info.txt || true
echo >> build_info.txt
sha256sum output_dir/* >> build_info.txt
sha256sum output_dir/* > output_dir/SHA256SUMS
