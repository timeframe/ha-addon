# Timeframe

An e-paper calendar, weather, and smart home family dashboard

![Timeframe display in phone nook](https://hawksley.org/img/posts/2026-02-17-timeframe/nook-wide.jpg)

## Supported displays

- Visionect [Place & Play 13](https://www.visionect.com/shop/place-play-13/) / [Joan 13 Pro](https://getjoan.com/shop/joan-13-pro/) - designed for 10m update interval
- Boox [Mira Pro 25.3"](https://shop.boox.com/products/boox-mira-procolor-version) - Real-time updates via WebSocket
- Boox [Mira 13.3"](https://shop.boox.com/products/boox-mira) - Real-time updates via WebSocket
- TRMNL [(OG)](https://shop.trmnl.com/collections/devices/products/trmnl)
- TRMNL (X)
- reTerminal E1001 7.5"
- reTerminal E1003 10.3"

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
| `sensor.timeframe_top_right_*` | None | Displays items in the top-right corner. State format: `icon,label(optional),rotation(optional)` (e.g. `door-open,Front Door`). Labels containing underscores are automatically humanized. Return multiple items for a single sensor by using newlines. Rotation is a degree value for the icon (e.g. for wind direction). |
| `sensor.timeframe_top_left_*` | None | Displays items in the top-left corner. State format: `icon,label(optional),rotation(optional)` |
| `sensor.timeframe_weather_status_*` | None | Displays weather status items. State format: `icon,label(optional),rotation(optional)`|
| `sensor.timeframe_daily_event_*` | None | Adds all-day events to the timeline. State format: `icon,label(optional)`. Return multiple events by using newlines. |
| `sensor.timeframe_media_player_entity_id` | Uses the first `media_player.*` entity | Set the state to a specific media player entity ID (e.g. `media_player.living_room`) to control which player's now-playing info is shown. |
| `sensor.timeframe_weather_entity_id` | Uses the first `weather.*` entity | Set the state to a specific weather entity ID (e.g. `weather.home`) to control which weather entity provides forecasts. |
| `sensor.timeframe_weather_feels_like_entity_id` | Uses `apparent_temperature` from the weather entity | Set the state to a specific sensor entity ID to override the feels-like temperature display. |

### Template helper examples

Here are some example template sensors:

#### `sensor.timeframe_top_left_status`

```jinja
{% if is_state('input_boolean.check_mailbox', 'on') %}
mailbox,Check mail
{% endif %}
```

#### `sensor.timeframe_top_left_unavailable_entities`

```jinja
{% if not is_state('sensor.solaredge_grid_power', 'unknown') %}
  {% set excluded_entity_ids = [
    'sensor.solaredge_current_power'
  ] %}

  {% set entities_list = states
  | selectattr('state', 'in', ['unavailable'])
  | selectattr('last_changed', 'lt', now() - timedelta(minutes=15))
  | map(attribute='entity_id')
  | reject('in', excluded_entity_ids)
  | list
  %}
  {% set data = namespace(dnamelist=[]) %}
  {% for entity_id in entities_list %}
  {% set device_name = device_attr(entity_id, 'name_by_user') | string %}
  {% if not (device_name == "None") %}
  {% set data.dnamelist = data.dnamelist + [ device_name ] %}
  {% endif %}
  {% endfor %}
  {% set devices = data.dnamelist | unique %}
  {%- for item in devices %}
  alert,{{item}}
  {%- endfor %}
{% endif %}
```

#### `sensor.timeframe_top_left_low_batteries`

```jinja
{% for state in states.sensor
|selectattr('attributes.device_class', '==', 'battery')
|selectattr('entity_id', 'search', 'battery_level') -%}
{% if states(state.entity_id) |int(100) <= 10 %}
battery-alert-variant-outline,{{ state.attributes.friendly_name |replace(' Battery Level', ' ') }}({{ states(state.entity_id) }}%)
{% endif %}
{%- endfor -%}
```

#### `sensor.timeframe_top_left_roborock_status`

```jinja
{% set vacuum_error = states('sensor.qrevo_curv_2_flow_vacuum_error') %}
{% set filter_time = states('sensor.qrevo_curv_2_flow_filter_time_left') %}
{% set sensor_time = states('sensor.qrevo_curv_2_flow_sensor_time_left') %}
{% set side_brush_time = states('sensor.qrevo_curv_2_flow_side_brush_time_left') %}
{% set main_brush_time = states('sensor.qrevo_curv_2_flow_main_brush_time_left') %}
{% set dock_error = states('sensor.qrevo_curv_2_flow_dock_dock_error') %}

{% if vacuum_error not in ["none", "ok", "unknown", "unavailable"] %}
robot,{{ vacuum_error }}
{% endif %}

{% if is_number(filter_time) and filter_time | float < 10 %}
robot,Clean air filter
{% endif %}

{% if is_number(sensor_time) and sensor_time | float < 10 %}
robot,Clean sensors
{% endif %}

{% if is_number(side_brush_time) and side_brush_time | float < 10 %}
robot,Replace side brushes
{% endif %}

{% if is_number(main_brush_time) and main_brush_time | float < 10 %}
robot,Replace main brush
{% endif %}

{% if is_state('sensor.qrevo_curv_2_flow_status', 'idle') or is_state('sensor.qrevo_curv_2_flow_status', 'charger_disconnected') %}
robot,Return to charger
{% endif %}

{% if dock_error not in ["ok", "unknown", "unavailable"] %}
robot,{{ dock_error }}
{% endif %}
```

#### `sensor.timeframe_top_left_open_doors`

```jinja
{% for sensor in ['binary_sensor.deck_door_sensor_opening','binary_sensor.alley_gate_door_sensor_opening','binary_sensor.west_gate_door_sensor_opening','binary_sensor.mudroom_door_sensor_opening','binary_sensor.utility_door_sensor_opening','binary_sensor.balcony_door_sensor_opening'] %}
  {% if is_state(sensor, 'on') %}
    door-open,{{ sensor|replace('binary_sensor.', '')|replace('_door_sensor_opening', '')|capitalize|replace('_', ' ') }}
  {% endif %}
{% endfor %}
```

#### `sensor.timeframe_top_left_laundry_status`

```jinja
{% if is_state('input_boolean.laundry_washer_needs_changed', 'on') %}
  {% set elapsed = as_timestamp(now()) - as_timestamp(states.input_boolean.laundry_washer_needs_changed.last_changed) %}
  {% set total_minutes = ((elapsed + 150) // 300 * 5) | int %}
  {% set days = total_minutes // 1440 %}
  {% set hours = total_minutes % 1440 // 60 %}
  {% set minutes = total_minutes % 60 %}
washing-machine,Washer{% if total_minutes > 0 %} ({% if days %}{{ days }}d{% endif %}{% if hours %}{{ hours }}h{% endif %}{% if minutes %}{{ minutes }}m{% endif %}){% endif %}
{% endif %}
```

#### `sensor.timeframe_top_left_door_locks`

```jinja
{% set doors = [
  ('Front', 'binary_sensor.front_door_sensor_opening', 'input_boolean.front_door_locked'),
  ('Patio', 'binary_sensor.patio_door_sensor_opening', 'input_boolean.patio_door_locked'),
  ('Alley', 'binary_sensor.alley_door_sensor_opening', 'input_boolean.alley_door_locked')
] %}
{% for name, door, lock in doors %}
  {% if is_state(door, 'on') and is_state(lock, 'on') %}
lock-alert,{{ name }}
  {% elif is_state(door, 'on') %}
door-open,{{ name }}
  {% elif is_state(lock, 'off') %}
lock-open-variant,{{ name }}
  {% endif %}
{% endfor %}

{% if is_state('binary_sensor.utility_chest_freezer_door_opening', 'on') %}
door-open,Chest freezer
{% endif %}

{% if is_state('binary_sensor.esphome_mailbox_mailbox_door', 'on') %}
door-open,Mailbox
{% endif %}

{% if is_state('cover.ratgdov25i_4b0f97_door', 'open') %}
garage-open,Single
{% endif %}

{% if is_state('cover.ratgdov25i_4b0f8a_door', 'open') %}
garage-open-variant,Double
{% endif %}
```

#### `sensor.timeframe_top_left_backup_battery_status`

```jinja
{% if is_state('sensor.solaredge_grid_power', 'unknown') %}
battery,Backup {{ states('sensor.solaredge_storage_level') }}%
{% endif %}
```

#### `sensor.timeframe_top_left_dishwasher_needs_attention`

```jinja
{% set power = states('sensor.kitchen_dishwasher_switched_outlet_power') %}
{% if is_number(power) and power | float < 2 and now().hour > 19 %}
dishwasher,Run the dishwasher!
{% endif %}
```

#### `sensor.timeframe_top_left_heat_pump_status`

```jinja
{% if not is_state('select.main_heat_source', 'heat pump only') %}
heat,Main HVAC {{ states("select.main_heat_source") }}
{% endif %}
{% if not is_state('select.upstairs_heat_source', 'heat pump only') %}
heat,Upstairs HVAC {{ states("select.upstairs_heat_source") }}
{% endif %}
```

#### `sensor.timeframe_weather_status_uv`

```jinja
{% set uv = states('sensor.weather_station_uv_index') | float(-1) %}
{% if uv > 3 %}
weather-sunny-alert,{{ uv | int }}
{% endif %}
```

#### `sensor.timeframe_weather_status_wind_gust`

```jinja
{% if states('sensor.weather_station_wind_gust') | int > 10 %}
arrow-up,{{states('sensor.weather_station_wind_gust') | int}},{{states('sensor.weather_station_wind_direction_average') | int - 45 }}
{% endif %}
```

#### `sensor.timeframe_top_right_bird`

```jinja
bird,{{ states('sensor.least_recently_seen_bird') }}
```

#### `sensor.timeframe_weather_status_lightning`

```jinja
{% set counter = states.sensor.blitzortung_lightning_counter %}
{% set distance = states('sensor.blitzortung_lightning_distance') %}
{% if int(counter.state, 0) > 0 and
      now() - counter.last_changed < timedelta(minutes=15) %}
flash-alert,{{ distance | int }}mi
{% endif %}
```

#### `sensor.timeframe_daily_event_ages`

```jinja
{% set today = now().date() %}

{% set first = strptime("2020-01-01", "%Y-%m-%d").date() %}
{% set first_before_anniversary = today.month < first.month or (today.month == first.month and today.day < first.day) %}
{% set first_years = today.year - first.year - (1 if first_before_anniversary else 0) %}
{% set first_anniversary = first.replace(year=first.year + first_years) %}
{% set first_months = (today.year - first_anniversary.year) * 12 + today.month - first_anniversary.month - (1 if today.day < first_anniversary.day else 0) %}
{% set first_month_index = first_anniversary.month - 1 + first_months %}
{% set first_cursor = strptime("%04d-%02d-%02d" | format(first_anniversary.year + first_month_index // 12, first_month_index % 12 + 1, first.day), "%Y-%m-%d").date() %}
{% set first_days = (today - first_cursor).days %}
numeric-1-circle,{% if first_years %}{{ first_years }}y{% endif %}{% if first_months %}{{ first_months }}m{% endif %}{% if first_days >= 7 %}{{ first_days // 7 }}w{% endif %}{% if first_days % 7 %}{{ first_days % 7 }}d{% endif %}{% if not first_years and not first_months and not first_days %}0d{% endif %}

{% set second = strptime("2022-01-01", "%Y-%m-%d").date() %}
{% set second_before_anniversary = today.month < second.month or (today.month == second.month and today.day < second.day) %}
{% set second_years = today.year - second.year - (1 if second_before_anniversary else 0) %}
{% set second_anniversary = second.replace(year=second.year + second_years) %}
{% set second_months = (today.year - second_anniversary.year) * 12 + today.month - second_anniversary.month - (1 if today.day < second_anniversary.day else 0) %}
{% set second_month_index = second_anniversary.month - 1 + second_months %}
{% set second_cursor = strptime("%04d-%02d-%02d" | format(second_anniversary.year + second_month_index // 12, second_month_index % 12 + 1, second.day), "%Y-%m-%d").date() %}
{% set second_days = (today - second_cursor).days %}
numeric-2-circle,{% if second_years %}{{ second_years }}y{% endif %}{% if second_months %}{{ second_months }}m{% endif %}{% if second_days >= 7 %}{{ second_days // 7 }}w{% endif %}{% if second_days % 7 %}{{ second_days % 7 }}d{% endif %}{% if not second_years and not second_months and not second_days %}0d{% endif %}
```

#### `sensor.timeframe_weather_feels_like_entity_id`

```jinja
sensor.weather_station_feels_like
```

#### `sensor.timeframe_media_player_entity_id`

```jinja
media_player.sonos_amp_2
```

#### `sensor.timeframe_weather_status_open_windows`

```jinja
{% set temp = states('sensor.weather_station_feels_like') | int %}
{% set aqi = states('sensor.airnow_air_quality_index') | int %}
{% set now = now().time() %}
{% set start = strptime('06:00', '%H:%M').time() %}
{% set end = strptime('20:00', '%H:%M').time() %}
{% if aqi < 70 and temp > 63 and temp < 71 and start <= now < end %}
window-open
{% endif %}
```

#### `sensor.timeframe_top_left_solofolio_status`

```jinja
{% if not is_state('input_text.solofolio_status', 'ok') %}
web-cancel, SoloFolio unhealthy
{% endif %}

{% if not is_state('input_text.timeframe_status', 'ok') %}
web-cancel, Timeframe unhealthy
{% endif %}

{% if states('input_number.solofolio_unread_support_messages') | int > 0 %}
email-outline, SoloFolio message
{% endif %}
```

#### `sensor.timeframe_top_left_dryer_status`

```jinja
{% if is_state('input_boolean.laundry_dryer_needs_changed', 'on') %}
  {% set elapsed = as_timestamp(now()) - as_timestamp(states.input_boolean.laundry_dryer_needs_changed.last_changed) %}
  {% set total_minutes = ((elapsed + 150) // 300 * 5) | int %}
  {% set days = total_minutes // 1440 %}
  {% set hours = total_minutes % 1440 // 60 %}
  {% set minutes = total_minutes % 60 %}
tumble-dryer,Dryer{% if total_minutes > 0 %} ({% if days %}{{ days }}d{% endif %}{% if hours %}{{ hours }}h{% endif %}{% if minutes %}{{ minutes }}m{% endif %}){% endif %}
{% endif %}
```

#### `sensor.timeframe_top_left_dog_bowl_status`

```jinja
{% if is_state('binary_sensor.dog_bowl_water_detected', 'off') %}
paw,Water low
{% endif %}
```

#### `sensor.timeframe_top_left_rav4_status`

```jinja
{% if is_state('device_tracker.garage_rav4_beacon', 'home') and is_state('sensor.garage_ev_charger_west_status', 'not_connected') %}
charging-station,RAV4 unplugged
{% endif %}
```

#### `sensor.timeframe_top_left_groceries_status`

```jinja
{% if is_state('input_boolean.bring_in_groceries', 'on') %}
basket,Bring in groceries
{% endif %}
```

#### `sensor.timeframe_top_left_printer_status`

```jinja
{% set toner = states('sensor.away_room_printer_black_toner_remaining') %}
{% if is_number(toner) and toner | float < 25 %}
print,Printer ink low
{% endif %}
```

#### `sensor.timeframe_top_left_nas_status`

```jinja
{% set temperature = states('sensor.hawksley_nas_temperature') %}
{% if is_number(temperature) and temperature | float < 1 %}
alert,NAS Offline
{% endif %}
```

#### `sensor.timeframe_top_left_offline_status`

```jinja
{% if not is_state('binary_sensor.8_8_8_8', 'on') %}
alert,Offline
{% endif %}
```

#### `sensor.timeframe_top_left_joel_listening_status`

```jinja
{% if is_state('sensor.joelhawksley_audio_state', 'input') %}
video,Meeting
{% elif is_state('sensor.joelhawksley_audio_state', 'output') %}
headphones,Listening
{% endif %}
```

#### `sensor.timeframe_top_left_open_door_for_robot`

```jinja
{% if is_state('binary_sensor.away_room_door_sensor_opening', 'off') and now().hour > 19 %}
door-closed,Open Door for robot
{% endif %}
```

#### `sensor.timeframe_weather_status_air_quality_warning`

```jinja
{% set aqi = states('sensor.honeysuckle_air_quality_aqi_us_aqi') | int %}
{% if aqi > 100 %}
face-mask-outline,{{ aqi }}
{% elif aqi > 50 %}
air-filter,{{ aqi }}
{% endif %}
```

#### `sensor.timeframe_top_left_solar_power_warning`

```jinja
{% set uv = states('sensor.weather_station_uv_index') %}
{% set solar_kw = states('sensor.solaredge_solar_power') %}
{% if is_number(uv) and is_number(solar_kw) and uv | float >= 4 and solar_kw | float < 0.5 %}
solar-power,UV >4 but low solar output!
{% endif %}
```

## Calendar events

### Event description tokens

You can customize how an individual calendar event renders by adding one or more tokens to its **description**. Tokens are usually placed on their own line and are stripped from any text shown on the display. Icon names come from [Material Design Icons](https://pictogrammers.com/library/mdi/) (without the `mdi-` prefix).

| Token | Description |
|---|---|
| `timeframe-omit` | Hides this event from the display. |
| `timeframe-icon:NAME` | Sets the event's icon, e.g. `timeframe-icon:soccer`. An `mdi-` prefix is accepted and ignored. |
| `timeframe-title:TEXT` | Overrides the displayed title without changing the real event title. |
| `timeframe-only:TOKENS` | Shows the event only on the listed devices. `TOKENS` is a comma-separated list of device names or ids, e.g. `timeframe-only:Kitchen, 12`. |
| `timeframe-banner` (or `#banner`) | Shows the event as a full-width banner while it is active (see below). |
| `timeframe-countdown:N` | Adds an all-day "(in Xd)" reminder on each of the `N` days leading up to the event (never on/after the event day). `N` is a positive number (up to 999). Honored by the hosted Timeframe app. |

A recurring event whose title ends with a four-digit year in parentheses, e.g. `Ada (1990)`, renders that year as an elapsed count (`Ada (35)`) — this is how birthdays and anniversaries show an age.

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

Create `config/timeframe.yml` from `config/timeframe.yml.example` with your settings.

### Environment variables

| Variable | Description |
|---|---|
| `VISIONECT_SERVER` | **Experimental.** Set to `"true"` to start the Visionect TCP protocol server alongside Puma. Required for Visionect Place & Play / Joan 13 Pro devices. |

### Setup

1) `bundle install`
2) `bin/rails s`
3) Visit [http://localhost:3000](http://localhost:3000)

### Testing

`bin/rails test`

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) — see [LICENSE.md](LICENSE.md) for details.
