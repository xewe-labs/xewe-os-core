// SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
// SPDX-License-Identifier: GPL-3.0-only
// xewe-os-core/src/XeWeCore/Config.h
//
// The core's configuration values (doc/config.md). Pure preprocessor and no includes, so every
// header can read it. Each value is a fallback: a build flag, the project's Config.h or the
// tools' generated headers define the name first and win.
#pragma once

// ---- runtime defaults ----

// Serial baud rate (SerialPortConfig::baud_rate), bits per second
#ifndef XEWE_CORE_SERIAL_BAUD
#define XEWE_CORE_SERIAL_BAUD 115200
#endif

// Serial TX buffer (SerialPortConfig::tx_buffer_size), bytes, set before Serial.begin
#ifndef XEWE_CORE_SERIAL_TX_BUF
#define XEWE_CORE_SERIAL_TX_BUF 2048
#endif

// Serial RX buffer (SerialPortConfig::rx_buffer_size), bytes; one input burst must fit
#ifndef XEWE_CORE_SERIAL_RX_BUF
#define XEWE_CORE_SERIAL_RX_BUF 1024
#endif

// Delay after opening the port (SerialPortConfig::startup_delay_ms), ms; 0 on a real UART
#ifndef XEWE_CORE_SERIAL_DELAY_MS
#define XEWE_CORE_SERIAL_DELAY_MS 1000
#endif

// Echo typed characters back (SerialPortConfig::echo), 0 or 1
#ifndef XEWE_CORE_SERIAL_ECHO
#define XEWE_CORE_SERIAL_ECHO 1
#endif

// Print the ASCII banner at boot (OsConfig::print_banner), 0 or 1
#ifndef XEWE_CORE_PRINT_BANNER
#define XEWE_CORE_PRINT_BANNER 1
#endif

// ---- first-boot values ----

// Device name (system/device_name), string literal, up to 254 characters; suggested at first boot
#ifndef XEWE_CORE_DEVICE_NAME
#define XEWE_CORE_DEVICE_NAME "xewe-device"
#define XEWE_CORE_DEVICE_NAME_PROMPT 1
#endif

// ---- compile-time constants ----

// Serial line buffer (SerialPort::INPUT_BUFFER_SIZE), bytes including the terminator, 2 to 256
#ifndef XEWE_CORE_INPUT_BUF_SIZE
#define XEWE_CORE_INPUT_BUF_SIZE 255
#endif

// Completed input lines queued (SerialPort::INPUT_QUEUE_LINES), 1 to 255
#ifndef XEWE_CORE_INPUT_QUEUE
#define XEWE_CORE_INPUT_QUEUE 4
#endif

// AsyncTimer progress recompute interval, ms; 0 recomputes on every call
#ifndef XEWE_CORE_TIMER_TICK_MS
#define XEWE_CORE_TIMER_TICK_MS 5
#endif
