#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

parameters=
if [ "${BUILD_AOSP_KERNEL}" = "1" ]; then
  echo "WARNING: BUILD_AOSP_KERNEL is deprecated." \
    "Use --kernel_package=@//aosp instead." >&2
  parameters="--kernel_package=@//aosp"
fi

if [ "${BUILD_STAGING_KERNEL}" = "1" ]; then
  echo "WARNING: BUILD_STAGING_KERNEL is deprecated." \
    "Use --kernel_package=@//aosp-staging instead." >&2
  parameters="--kernel_package=@//aosp-staging"
fi

tools/bazel run \
  --config=stamp \
  --config=raviole \
  --kernel_package=@//aosp \
  --//build/kernel/kleaf:use_prebuilt_gki=0 \
  --//aosp:use_prebuilt_gki=false \
  //private/devices/google/raviole:gs101_raviole_dist

# -----------------------------------------------------------------------------
# Why these Bazel arguments exist (READ BEFORE REMOVING ANYTHING)
#
# This build intentionally DISABLES prebuilt GKI kernels and forces a FULL
# source-built kernel image + modules. This is REQUIRED for any real kernel
# development, localversion changes, or config validation.
#
# Background (the critical bit):
# - Pixel / AOSP kernels use Kleaf "mixed builds" by default.
# - In a mixed build:
#     * The boot kernel Image comes from PREBUILT GKI artifacts
#     * Only vendor_dlkm modules are rebuilt from source
# - This causes:
#     * `uname -r` to show a stock Google kernel
#     * CONFIG_LOCALVERSION to appear in modules only
#     * Guaranteed vermagic mismatch between kernel and vendor_dlkm
#
# Therefore: prebuilts MUST be disabled explicitly.
#
# Argument breakdown:
#
# --config=stamp
#   Enables build stamping so the kernel embeds:
#     - git commit hash
#     - dirty tree marker (if applicable)
#   Without this, even source-built kernels lose provenance.
#
# --config=raviole
#   Selects Pixel 6 (GS101 / raviole) device configuration:
#     - defconfigs
#     - DTBOs / DTBs
#     - vendor_dlkm layout
#
# --kernel_package=@//aosp
#   Forces the kernel package source to AOSP (not staging).
#   This is REQUIRED when building the kernel from source.
#
# --//build/kernel/kleaf:use_prebuilt_gki=0
#   GLOBAL Kleaf override.
#   Prevents the build system from selecting prebuilt GKI kernels.
#   This disables the path:
#     @gki_prebuilts//Image.lz4
#
# --//aosp:use_prebuilt_gki=false
#   AOSP-local override.
#   Prevents fallback selection of prebuilt kernels inside aosp/BUILD.bazel.
#   BOTH flags are required because either one can enable prebuilts.
#
# Result of these flags:
#   - Kernel Image is compiled from THIS SOURCE TREE
#   - CONFIG_LOCALVERSION appears in:
#       * Image.lz4
#       * uname -r
#       * vendor_dlkm vermagic
#   - Kernel + modules are version-aligned
#
# If you remove these flags:
#   You are no longer building a real kernel.
#   You are repackaging Google's prebuilt GKI.
# -----------------------------------------------------------------------------
