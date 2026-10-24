// SPDX-FileCopyrightText: 2026 Maxim Dokukin (maxdokukin.com)
// SPDX-License-Identifier: GPL-3.0-only
// xewe-os-core/src/XeWeCore/Utils/Listeners.h
#pragma once

#include <cstddef>

namespace xewe {

template <typename Iface, std::size_t N = 4> class ListenerSet {
    static_assert(N > 0, "ListenerSet needs a capacity of at least 1");

public:
    // true when added or already present (no duplicates); false for nullptr or when full
    bool add(Iface* listener) {
        if (listener == nullptr)
            return false;
        for (Iface* l : items)
            if (l == listener)
                return true;
        for (Iface*& l : items) {
            if (l == nullptr) {
                l = listener;
                return true;
            }
        }
        return false;
    }

    // true when it was registered; its slot is reused by the next add()
    bool remove(Iface* listener) {
        if (listener == nullptr)
            return false;
        for (Iface*& l : items) {
            if (l == listener) {
                l = nullptr;
                return true;
            }
        }
        return false;
    }

    bool contains(const Iface* listener) const {
        if (listener == nullptr)
            return false;
        for (Iface* l : items)
            if (l == listener)
                return true;
        return false;
    }

    std::size_t size() const {
        std::size_t n = 0;
        for (Iface* l : items)
            n += (l != nullptr);
        return n;
    }

    static constexpr std::size_t capacity() {
        return N;
    }

    // calls fn(Iface&) for every listener in slot order; each slot is re-read before its call,
    // so a listener removed by an earlier callback is not called
    template <typename F> void notify(F&& fn) const {
        for (std::size_t i = 0; i < N; ++i) {
            Iface* l = items[i];
            if (l != nullptr)
                fn(*l);
        }
    }

private:
    Iface* items[N] = {};
};

} // namespace xewe
