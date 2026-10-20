// SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
// SPDX-License-Identifier: GPL-3.0-only
// xewe-os-core/tests/unit/probe/Config.probe.cpp

// Config.h on its own: every default, and XEWE_CORE_DEVICE_NAME_PROMPT only while the device name
// is not pre-answered. run.sh builds this once plain and once with -DXEWE_CORE_DEVICE_NAME="x".
#ifdef XEWE_CORE_DEVICE_NAME
#define PROBE_NAME_PREANSWERED 1
#else
#define PROBE_NAME_PREANSWERED 0
#endif

#include <XeWeCore/Config.h>

namespace {
constexpr bool same(const char* a, const char* b) {
    return *a == *b && (*a == '\0' || same(a + 1, b + 1));
}
} // namespace

static_assert(XEWE_CORE_SERIAL_BAUD == 115200, "serial baud");
static_assert(XEWE_CORE_SERIAL_TX_BUF == 2048, "serial tx buffer");
static_assert(XEWE_CORE_SERIAL_RX_BUF == 1024, "serial rx buffer");
static_assert(XEWE_CORE_SERIAL_DELAY_MS == 1000, "serial startup delay");
static_assert(XEWE_CORE_SERIAL_ECHO == 1, "serial echo");
static_assert(XEWE_CORE_INPUT_BUF_SIZE == 255, "line buffer");
static_assert(XEWE_CORE_INPUT_QUEUE == 4, "line queue");
static_assert(XEWE_CORE_TIMER_TICK_MS == 5, "timer tick");

#if PROBE_NAME_PREANSWERED
#ifdef XEWE_CORE_DEVICE_NAME_PROMPT
#error "a pre-answered device name must not prompt"
#endif
static_assert(same(XEWE_CORE_DEVICE_NAME, "x"), "the build's name wins");
#else
#ifndef XEWE_CORE_DEVICE_NAME_PROMPT
#error "without a pre-answered name the first boot prompts"
#endif
static_assert(same(XEWE_CORE_DEVICE_NAME, "xewe-device"), "suggested device name");
#endif
