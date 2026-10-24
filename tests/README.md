# XeWeCore tests

`unit/` holds the host tests. `run.sh` builds the probes in `unit/probe/` and the tests in
`unit/test/` against the stand-ins in `unit/shim/`, once at `c++17` and once at `gnu++2b`, and
runs them. Tests that need ArduinoJson are in `unit/test/json/`.

```sh
ARDUINOJSON_SRC=<path to ArduinoJson>/src tests/unit/run.sh
```

`board/` holds the pytest files that run on a real board through the xewe-os-tools plugin, from
an xewe project with the board attached. A parser, tokenizer or FlexData case has a twin in both
folders, such as `unit/test/test_parsers.cpp` and `board/test_hooks_utils.py`, so change both
together.

[doc/TESTS.md](../doc/TESTS.md) has the board command, the preconditions and what each file
covers.
