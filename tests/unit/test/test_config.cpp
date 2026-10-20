// SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
// SPDX-License-Identifier: GPL-3.0-only
// xewe-os-core/tests/unit/test/test_config.cpp

// The components take their defaults from Config.h.

#include "test.h"

#include <XeWeCore/Config.h>
#include <XeWeCore/Serial/Serial.h>
#include <XeWeCore/Utils/AsyncTimer.h>

TEST(config_serial_port_defaults) {
    const xewe::SerialPortConfig cfg{};
    CHECK_EQ(cfg.baud_rate, static_cast<unsigned long>(XEWE_CORE_SERIAL_BAUD));
    CHECK_EQ(cfg.tx_buffer_size, static_cast<std::size_t>(XEWE_CORE_SERIAL_TX_BUF));
    CHECK_EQ(cfg.rx_buffer_size, static_cast<std::size_t>(XEWE_CORE_SERIAL_RX_BUF));
    CHECK_EQ(cfg.startup_delay_ms, static_cast<uint32_t>(XEWE_CORE_SERIAL_DELAY_MS));
    CHECK_EQ(cfg.echo, XEWE_CORE_SERIAL_ECHO != 0);
}

TEST(config_async_timer_tick) {
    static_assert(XEWE_CORE_TIMER_TICK_MS > 0, "the test needs a throttle");
    host::set_millis(1000);
    xewe::AsyncTimer<double> t(1000, 0.0, 1000.0); // value == elapsed ms
    t.initiate();
    CHECK(t.get_current_value() == 0.0); // first sample is not throttled
    host::advance(XEWE_CORE_TIMER_TICK_MS - 1);
    CHECK(t.get_current_value() == 0.0); // within one tick: not recomputed
    host::advance(1);
    CHECK(t.get_current_value() == double(XEWE_CORE_TIMER_TICK_MS)); // one tick: recomputed
}
