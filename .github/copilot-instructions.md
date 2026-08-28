# Copilot Instructions

## Migrations

All database migrations must be added to `ha-addon/engine/db/migrate/` using sequential numbering (001, 002, ...). Never add migrations to `cloud/db/migrate/`. The engine migrations are shared by both apps via the engine's `append_migrations` initializer.

After running migrations, copy the schema: `cp ha-addon/engine/db/schema.rb cloud/db/schema.rb` (ha-addon/db/schema.rb is a symlink to the engine's).

## Documentation

Keep `ha-addon/README.md` in sync with the code whenever behavior changes. Check these sources of truth:

- **Supported displays:** `Device::SUPPORTED_MODELS` in `ha-addon/engine/app/models/device.rb`.
- **Add-on config options:** the `schema` block in `ha-addon/config.json` (must match the units accepted by `HomeAssistantApi`).
- **Standalone env vars:** `docker-compose.yml` and `TimeframeConfig` defaults.
- **Sensor entities:** the `sensor.timeframe_*` methods in `ha-addon/app/apis/home_assistant_api.rb`.
- **Event description tokens:** the `TIMEFRAME_*` patterns and token handling in `ha-addon/engine/app/models/device_event.rb`.

When any of these change, update the corresponding README table/section in the same change.

## Validation Checklist

Before considering any task complete, always run all of the following checks and fix any issues:

Run every command through `mise`. Run both complete test suites even if a change appears isolated to only one app, because `cloud` and `ha-addon` consume the shared engine.

1. **Tests & Coverage (cloud):** `cd cloud && mise exec -- bundle exec rake test` — all tests and coverage checks must pass.
2. **Tests & Coverage (ha-addon):** `cd ha-addon && mise exec -- bundle exec rake test` — all tests and coverage checks must pass.
3. **StandardRB (cloud):** `cd cloud && mise exec -- bundle exec standardrb` — no violations.
4. **StandardRB (ha-addon):** `cd ha-addon && mise exec -- bundle exec standardrb` — no violations.
5. **Herb (cloud):** `cd cloud && mise exec -- bundle exec herb analyze .` — all `.html.erb` files must be clean.
6. **Herb (ha-addon):** `cd ha-addon && mise exec -- bundle exec herb analyze .` — all `.html.erb` files must be clean.
