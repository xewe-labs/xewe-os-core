#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
# SPDX-License-Identifier: GPL-3.0-only
# xewe-os-core/tests/unit/run.sh
#
# Host-native checks for the hardware-free parts of XeWeCore: Utils, Serial, Cli and FlexData, and
# at gnu++2b Nvs and Settings against an in-memory NVS shim. Needs ARDUINOJSON_SRC (ArduinoJson's src/).
# Builds the compile probes and the unit tests with the host g++ against the
# Arduino/FreeRTOS shim, once at -std=c++17 (exercises the xewe::span fallback)
# and once at -std=gnu++2b (what the ESP32 core uses), and runs the tests.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../src"
CXX="${CXX:-g++}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

FLAGS=(-Wall -Wextra -fno-exceptions -I "$HERE/shim" -I "$SRC")
LIB_SRCS=("$SRC/XeWeCore/Serial/Serial.cpp" "$SRC/XeWeCore/Cli/Cli.cpp")

# FlexData, Nvs and Settings tests need ArduinoJson (header-only): ARDUINOJSON_SRC is its src/ directory.
if [ ! -f "${ARDUINOJSON_SRC:-}/ArduinoJson.h" ]; then
    echo "run.sh: set ARDUINOJSON_SRC to ArduinoJson's src/ (git clone --depth 1 --branch v7.4.3 https://github.com/bblanchon/ArduinoJson)" >&2
    exit 1
fi
FLAGS+=(-I "$ARDUINOJSON_SRC")
JSON_TESTS=("$HERE"/test/json/*.cpp)

for std in c++17 gnu++2b; do
    echo "== $std: probes"
    for p in "$HERE"/probe/*.probe.cpp; do
        "$CXX" -std="$std" "${FLAGS[@]}" -c "$p" -o "$OUT/$(basename "$p").$std.o"
        echo "   ok $(basename "$p")"
    done
    "$CXX" -std="$std" "${FLAGS[@]}" -DXEWE_CORE_DEVICE_NAME='"x"' -c "$HERE/probe/Config.probe.cpp" \
        -o "$OUT/Config.preanswered.$std.o"
    echo "   ok Config.probe.cpp with XEWE_CORE_DEVICE_NAME (no prompt)"

    echo "== $std: host-includable headers (standard library only, no Arduino shim)"
    for h in Config.h Utils/Color.h Utils/String.h Utils/Pins.h Utils/Listeners.h; do
        printf '#include <XeWeCore/%s>\n' "$h" | "$CXX" -std="$std" -Wall -Wextra -fno-exceptions -I "$SRC" -x c++ -fsyntax-only -
        echo "   ok $h"
    done

    echo "== $std: tests"
    "$CXX" -std="$std" "${FLAGS[@]}" "$HERE"/test/*.cpp "${JSON_TESTS[@]}" "${LIB_SRCS[@]}" -o "$OUT/tests.$std"
    "$OUT/tests.$std"
done
echo "== all unit checks passed"
