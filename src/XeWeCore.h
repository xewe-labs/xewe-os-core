// SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
// SPDX-License-Identifier: GPL-3.0-only
// xewe-os-core/src/XeWeCore.h
//
// Umbrella header: the one include a sketch needs. It also makes the library
// discoverable, so XeWeCore/<Part>/*.h headers can be included after it.
#pragma once

#include "XeWeCore/Utils/Utils.h"
#include "XeWeCore/Serial/Serial.h"
#include "XeWeCore/Cli/Cli.h"
#include "XeWeCore/Nvs/FlexData.h"
#include "XeWeCore/Nvs/Nvs.h"
#include "XeWeCore/Settings/Settings.h"
#include "XeWeCore/Module/Module.h"
#include "XeWeCore/Os/XeWeOs.h"
