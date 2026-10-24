# XeWeCore examples

Arduino sketches for the XeWeCore library, one folder each. `01_Hello` and `02_MyModule` teach,
and `11_Utils` to `15_Os` show one part of the core each. What each one shows is in
[doc/EXAMPLES.md](../doc/EXAMPLES.md).

Compile one against this checkout:

```sh
arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc --library . examples/01_Hello
```

[doc/TESTS.md](../doc/TESTS.md#example-builds) has the full FQBN that CI uses for each chip.
