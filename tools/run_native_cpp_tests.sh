#!/usr/bin/env bash
# Host tests for the native DSP code (no Android needed). Built with AddressSanitizer
# and UBSan so an out-of-bounds access or undefined behaviour fails the run.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/apex_cw_interference_test"
c++ -std=c++17 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined \
    -Wall -Wextra android/android/app/src/test/cpp/interference_test.cpp -o "$out"
"$out"
