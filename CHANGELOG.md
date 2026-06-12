## [2.14.0] - 2026-06-11

### Added
- New "1-Day" template: single-day landscape layout with daily weather, clothing forecast, and events
- Per-calendar selection on device settings: choose which Home Assistant calendars contribute events to a device (all included by default), with an optional per-calendar keyword filter to only show matching events
- Per-hour selection for hourly conditions: pick exactly which hours show temperature/conditions events
- Configurable wind gust threshold per device
- Standalone Docker container support: run Timeframe outside the Home Assistant add-on via `docker-compose`, configured entirely through environment variables (including a remote Home Assistant URL)
- Page titles on web pages

### Changed
- Settings option labels simplified (e.g. "Show Icons" → "Icons", "Show Hourly Temperature Events" → "Hourly Conditions"); "Hide Dates" inverted to "Dates"
- Hourly conditions, precipitation, and wind toggles are hidden on the two-day template

### Fixed
- Screenshot service deadlock that could cause screenshot generation to hang
- Device preview and screenshot rotation for reTerminal E1003 and TRMNL X devices

### Removed
- 8-day template

## [2.13.0] - 2026-05-26

### Added
w- Individual toggles for precipitation and wind events on two-day and three-day templates (previously a single "Show Weather Events" toggle controlled both)
- "Hide Current Day After Time" option on two-day template: automatically advances to show tomorrow once the configured time passes (default 6:00 PM)
- Granular weather event toggles now respect the legacy `show_weather_events=false` setting for existing devices

### Changed
- Two-day template title wrapping is now suppressed when titles fit on a single line
- Two-day and three-day templates use a compact time format

### Fixed
- Deleting a device from the settings page redirected back to the now-deleted settings URL (404); now redirects to the dashboard with a confirmation notice

## [2.12.0] - 2026-05-18

### Added
- Device settings page with full configuration, preview, and screenshot management
- "Configure" button on device cards replaces the dropdown menu
- Live preview on settings page with date/time picker and prev/next day navigation
- Screenshot card with inline regenerate button (async, no page navigation)
- Device rename functionality on settings page
- Per-device event filter: comma-separated keywords to show only matching calendar events
- Precipitation probability percentage shown in precip event labels (e.g. "Rain 0.5\" 60%")
- Toggle to show/hide icons on two-day and three-day templates
- Auto-assign icons option (conditional on show icons being enabled)

### Changed
- Device card footer now shows "Updated X ago" instead of device model name
- Precipitation event threshold lowered from 20% to 10%
- Preview page removed as standalone route; functionality moved into settings page

### Fixed
- Clothing forecast: daily high guardrail prevents shorts recommendation when daily forecast high is below threshold
- Multi-day event denominator: non-daily events spanning multiple days now correctly show "1/2", "2/2" instead of "1/1", "2/1"
- CSS specificity fix for time column padding on two-day template
- Icon padding-left removed on two-day and three-day templates
- Allow `%` character in event summaries (was stripped by sanitization)

## [2.11.0] - 2026-05-16

### Added
- TRMNL X device support
- Clothing forecast (shorts/pants recommendation based on morning temperature)
- "Show all events" option on three-day template
- Weather event times and precipitation/wind ranges shown on three-day template

### Changed
- Three-day template layout: events rendered in a table with times, word-wrap instead of truncation
- Two-day template changed from "2-Day Portrait" to "2-Day" landscape layout
- Daily events now use timezone-aware day boundaries
- `DeviceEvent#all_day?` uses local timezone for midnight checks

### Fixed
- Hourly weather events not rendering when HA reports timestamps with `+00:00` instead of `Z` (e.g. Met.no)
- Precipitation events skipped when integration omits `precipitation_probability` (e.g. Met.no); now falls back to precipitation amount and condition
- Wind events skipped when integration omits `wind_gust_speed` (e.g. Met.no); now falls back to `wind_speed`
- Calendar events with blank UIDs now get a deterministic fallback ID
- Timezone handling for daily event start/end times
- Duplicate icon/label pairs in sensor displays
- Expiring pairing codes
- Setup flow compatibility issues
- Performance loading in production

## [2.10.0] - 2026-05-05

### Added
- Eight-day 1080p display template
- Battery level display on device cards
- Daily precipitation totals (rain/snow) shown on daily weather summary with icons
- Daily max wind gust shown on weather summary when ≥ 20mph

### Changed
- Pairing page moved to `/pair`

### Fixed
- Two-day template alignment; allow hiding dates via device configuration
- Image outline on calendar event attachments
- Realtime display refresh handling improvements
- Precip events with negligible amounts (rounding to 0.0) are no longer shown
- Fixed daily precipitation calculation for snow (snowfallAmount is depth, not liquid equivalent)

## [2.9.6] - 2026-04-29

### Fixed
- Fix docker build

## [2.9.5] - 2026-04-29

### Fixed
- Fix docker build

## [2.9.4] - 2026-04-29

### Fixed
- Fix docker build

## [2.9.3] - 2026-04-29

### Fixed
- Enable rails logging to aid in debugging

## [2.9.2] - 2026-04-29

### Fixed
- Fix docker build

## [2.9.1] - 2026-04-29

### Fixed
- Fix docker build

## [2.9.0] - 2026-04-29

### Added
- Two-day portrait display template for TRMNL and reTerminal E1001
- TRMNL API: capture device telemetry (firmware version, battery, RSSI) from request headers
- TRMNL API: added missing response fields (status, firmware_url, temperature_profile)
- Boox Mira 13.3" device support

### Fixed
- Fixed timezone handling in display templates (Date.current → timezone-aware)
- Deleting a device now destroys associated pending devices

## [2.8.0] - 2026-04-14

### Added
- Support label-less icons

## [2.7.0] - 2026-04-12

### Fixed
- Fix Postgres misconfiguration

## [2.6.0] - 2026-04-12

### Fixed
- Fixed broken docker build

## [2.5.0] - 2026-04-12

### Fixed
- Fixed broken docker build

## [2.4.0] - 2026-04-12

### Changed
- Split up repository to only include single-tenant functionality.

## [2.3.0] - 2026-04-07

### Fixed
- Fix bug where weather and calendar data was marked unhealthy and thus hidden before refresh interval.

## [2.2.0] - 2026-04-07

### Changed
- Display routes are now named `*/devices/*`.

## [2.1.0] - 2026-04-07

### Changed
- Move internal display route to be nested under location.

## [2.0.7] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.6] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.5] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.4] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.3] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.2] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.1] - 2026-04-06

### Fixed
- Fixed bug in Dockerfile that prevented build from working in Home Assistant.

## [2.0.0] - 2026-04-06

_Lots of breaking changes in this release, most notably moving the repository to [https://](https://github.com/timeframe/timeframe)._

### Added
- Token-authenticated display URLs for Visionect devices (`/d/:id?key=...`)
- Signed, expiring screenshot URLs for TRMNL devices (1-minute SGID)
- Rack::Attack rate limiting on display and pairing endpoints
- Device card grid with live preview on dashboard
- Confirmation modals for device deletion and URL regeneration
- Re-pair flow for Boox devices with disconnection detection (>1 hour)
- Device session tokens for Boox displays (one session per device)
- Action Cable with PostgreSQL adapter for real-time Mira display updates
- DisplayBroadcaster: push-based updates triggered by HA state changes
- Client-side clock, date, and top-of-hour flash for Mira displays
- Status page at `/status` for Home Assistant API diagnostics

### Changed
- Pairing and confirmation codes are now 6-digit numeric (were alphanumeric). Pairing codes expire after 15 minutes.
- Display templates are now stateless (all logic in DisplayContent/DemoDisplayContent)
- Mira polling replaced with Action Cable push (was 86,400 requests/day)

### Security
- Display URLs require authentication (session or token)
- Rack::Attack rate limiting on token displays and pairing
- Identical 401 responses prevent display enumeration
- Referrer-Policy: no-referrer on token display responses
- Device session tokens scoped per-device, rotated on re-pair
