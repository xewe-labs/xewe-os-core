# Stored data and interface behaviour

Devices in the field keep their NVS data across reflashes, and users and tools depend on the
console's exact behaviour. Both change only on purpose.

## Stored names and formats

Module ids, NVS namespaces, NVS keys and settings-table keys are 1 to 15 characters, the NVS
limit. Never rename or retype a stored key. That covers `is_enabled`, `not_first_boot`,
`init_complete`, `root/init_setup_flag`, `system/device_name` and every settings-table key. Also
leave alone `MAX_KEY_LEN`, the float encoding, any `FlexData` field list, `kBlobVersion` and the
`ESP_LOGE` tag `"XeWeNvs"`. Changing any of them makes devices lose their data.

## Interface behaviour

These change only together with their doc page, as a deliberate change that the release notes
announce:

- the CLI error strings and the two `execute` matching rules
- the prompt defaults and the bounded confirmations, 2 attempts of 15 s each
- the 254-character line, the 4-line queue and the whole-line drop of an over-long line
- CRLF output, and wrapping only when `message_width > 0`
- the `hsv_to_rgb` arithmetic and the strict `parse_hex_color`

## Docs are part of the change

A public function, lifecycle step, command, prompt, NVS key or build define that is added or
changed updates its page in the same change. The page is the component `README.md` under
`src/XeWeCore/`, or a file in `doc/`. `doc/` describes current behaviour only, with no history,
changelog or version tags.
