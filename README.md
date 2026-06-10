# Timeframe

An e-paper calendar, weather, and smart home family dashboard

![Timeframe display in phone nook](https://hawksley.org/img/posts/2026-02-17-timeframe/nook-wide.jpg)

## Supported displays

- Visionect [Place & Play 13](https://www.visionect.com/shop/place-play-13/) / [Joan 13 Pro](https://getjoan.com/shop/joan-13-pro/) - designed for 10m update interval
- Boox [Mira Pro](https://shop.boox.com/products/boox-mira-procolor-version) - Real-time updates via WebSocket
- TRMNL [(OG)](https://shop.trmnl.com/collections/devices/products/trmnl)

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**
2. Click the three-dot menu (⋮) → **Repositories**
3. Add this repository URL: `https://github.com/timeframe/ha-addon`
4. Find **Timeframe** in the add-on store and click **Install**
5. Click **Start**
6. Access the app at port 8099 (e.g. `http://homeassistant.local:8099`)

## Run as a standalone Docker container

Timeframe can also run as a regular Docker container, independent of the Home Assistant add-on system. All configuration comes from environment variables, and it can point at any reachable Home Assistant instance — local or remote.

You'll need a Home Assistant **long-lived access token**: in HA, open your profile → **Security** → **Long-Lived Access Tokens** → **Create Token**.

### Using Docker Compose

A ready-to-edit [`docker-compose.yml`](docker-compose.yml) is included. Set `TIMEFRAME_HOME_ASSISTANT_URL` and `TIMEFRAME_HOME_ASSISTANT_TOKEN`, then:

```
docker compose up -d --build
```

Open the dashboard at `http://localhost:8099`.

### Using docker run

```
docker build -t timeframe .

docker run -d \
  --name timeframe \
  -p 8099:8099 \
  -v timeframe-data:/data \
  -e TIMEFRAME_HOME_ASSISTANT_URL="http://192.168.1.50:8123" \
  -e TIMEFRAME_HOME_ASSISTANT_TOKEN="your_long_lived_access_token" \
  timeframe
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `TIMEFRAME_HOME_ASSISTANT_URL` | `http://homeassistant.local:8123` | Base URL of your Home Assistant instance. Use any reachable address, e.g. `http://192.168.1.50:8123`. |
| `TIMEFRAME_HOME_ASSISTANT_TOKEN` | _(required)_ | Home Assistant long-lived access token. Required when running standalone. |
| `TIMEFRAME_TEMPERATURE_UNIT` | `F` | `F` or `C`. |
| `TIMEFRAME_SPEED_UNIT` | `mph` | `mph` or `kph`. |
| `TIMEFRAME_PRECIPITATION_UNIT` | `in` | `in`, `mm`, or `cm`. |
| `SECRET_KEY_BASE` | _(auto-generated)_ | Secret used to encrypt sessions and stored data. If unset, a random key is generated and persisted to the `/data` volume on first run. |
| `PORT` | `8099` | Port the web interface listens on inside the container. |

Keep the `/data` volume across restarts — it holds the bundled Postgres database and the generated secret key.

> When installed as a Home Assistant add-on, Timeframe instead authenticates automatically via the Supervisor and reads unit options from the add-on configuration UI, so no environment variables are required in that mode.

## Configuration

The following entities can be created in Home Assistant to customize behavior. Icon names are from [Material Design Icons](https://pictogrammers.com/library/mdi/) (without the `mdi-` prefix).

| Entity ID | Default behavior | Description |
|---|---|---|
| `sensor.timeframe_top_right_*` | None | Displays items in the top-right corner. State format: `icon,label(optional),rotation(optional)` (e.g. `door-open,Front Door`). Labels containing underscores are automatically humanized. Return multiple items for a single sensor by using newlines. Rotation is a degree value for the icon (e.g. for wind direction). State format: `icon,label(optional),rotation(optional)` |
| `sensor.timeframe_top_left_*` | None | Displays items in the top-left corner. State format: `icon,label(optional),rotation(optional)` |
| `sensor.timeframe_weather_status_*` | None | Displays weather status items. State format: `icon,label(optional),rotation(optional)`|
| `sensor.timeframe_daily_event_*` | None | Adds all-day events to the timeline. State format: `icon,label(optional)` |
| `sensor.timeframe_media_player_entity_id` | Uses the first `media_player.*` entity | Set the state to a specific media player entity ID (e.g. `media_player.living_room`) to control which player's now-playing info is shown. |
| `sensor.timeframe_weather_entity_id` | Uses the first `weather.*` entity | Set the state to a specific weather entity ID (e.g. `weather.home`) to control which weather entity provides forecasts. |
| `sensor.timeframe_weather_feels_like_entity_id` | Uses `apparent_temperature` from the weather entity | Set the state to a specific sensor entity ID to override the feels-like temperature display. |

## Calendar events

### Private mode

A calendar event with the description `timeframe-private` will activate private mode for the duration of the event, hiding display content.

### Hiding specific events

To hide a specific event, include `timeframe-omit` in the description.

### Banner mode

To display a full-width banner at the bottom of the screen, include `timeframe-banner` or `#banner` in a calendar event's description. The banner appears while the event is active (between its start and end times).

- The event **title** becomes the banner heading.
- The rest of the **description** (after removing the tag) becomes the banner body. Basic HTML formatting (`<b>`, `<i>`, `<u>`, `<s>`) is supported; plain-text newlines are converted to line breaks.

**Example:** Create a calendar event titled "School Closed Today" with the description:

```
#banner
Due to inclement weather, <b>all schools</b> will be closed today. Stay safe!
```

## Local development

### Configuration:

Create `config/timeframe.yml` from `config/timeframe.yml.example with your settings.

### Environment variables

| Variable | Description |
|---|---|
| `VISIONECT_SERVER` | **Experimental.** Set to `"true"` to start the Visionect TCP protocol server alongside Puma. Required for Visionect Place & Play / Joan 13 Pro devices. |

### Setup

1) `bundle config set local.timeframe-core ../core`
2) `bundle install`
3) `rails s`
3) Visit [http://localhost:3000](http://localhost:3000)

### Testing

`bin/rails test`

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) — see [LICENSE.md](LICENSE.md) for details.
