# Timeframe Core

Shared Rails engine for [Timeframe](https://github.com/timeframe/ha-addon) e-paper display apps.

## Home Assistant sensor states

`HaSensorState.parts(state)` parses newline-separated, comma-delimited sensor
values into `[fields, original_line_index]` pairs. It trims fields and skips
blank values and Home Assistant's `unavailable` and `unknown` states.

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) — see [LICENSE.md](LICENSE.md) for details.
