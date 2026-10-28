# Decent Remote 0.3.5 API

[中文文档](../API.md)

This document describes the 0.3.5 service and dashboard. Parameter changes, status reads and stop commands use de1app's native controls. Remote start endpoints are disabled.

Change the access key on the tablet's plugin settings page. There is no remote key-change endpoint. A new installation defaults to `admin1234`; an existing key is preserved. A saved key takes effect immediately. The old key then returns 401 on v1 endpoints or 403 on legacy endpoints. Keys must contain 8–128 visible ASCII characters, with no whitespace. The web interface saves connection details in browser local storage only after successful authentication and only when the user selects **Remember connection**.

## Requests, authentication, and results

Use `Authorization: Bearer <token>` for `/api/v1/`. Query-string authentication is not accepted on v1 endpoints. Every non-GET request requires a unique `X-Request-ID`: 8–80 letters, digits, `_`, or `-`. Send `{}` for a POST with no parameters. Send no body when selecting a file with PUT. Request bodies use UTF-8; encode filenames in URLs as UTF-8.

The HTTP service supports GET, POST and PUT. GET and PUT must not include a body. Parameter updates use POST, not PATCH. Unknown fields are rejected. Use JSON numbers and booleans for those values; do not substitute arrays for scalar fields. A duplicate request ID returns 409 even if the first attempt failed. Changing the ID does not make a retry safe.

Common errors:

| HTTP status | Meaning |
|---|---|
| 400 | Invalid request format |
| 401 | Authentication failed on a v1 endpoint |
| 403 | Remote start is disabled, legacy authentication failed, or a browser origin was rejected |
| 404 | Endpoint, file, or request record does not exist |
| 405 | Method is not supported |
| 409 | Busy, conflict, or duplicate request |
| 413 | Request body or file is too large |
| 422 | Invalid parameters |
| 501 | Feature or dependency is unavailable |
| 502 | Send, apply, or save outcome is unknown |
| 503 | Access key is not configured correctly or the process request-record limit has been reached |

Error responses contain `error` and `message`. If app settings were updated before a device send or save failed, the API does not promise a rollback. `readback=app_cache` describes the app's cached state, not independent hardware confirmation.

### Request records and confirmation

`GET /api/v1/requests/{request_id}` returns a record held by the current process. It includes `in_flight` (whether the profile request is still in flight), `phase`, `accepted`, `app_applied`, `device_confirmed`, `confirmation_scope`, the HTTP status, and timestamps. Possible phases include:

`processing`, `accepted_unconfirmed`, `app_applied`, `frames_queued`, `frames_confirmed`, `frames_unconfirmed`, `unconfirmed_timeout`, `superseded`, `rejected`, and `outcome_unknown`.

`confirmation_scope=profile_frames_only` confirms only the corresponding native profile frames. It does not confirm beverage weight, actual flow, temperature stability, or completion of a physical action. When overlapping sends cannot be attributed to a request, the API does not grant definitive confirmation. A timeout means confirmation has not been observed; it does not prove a hardware failure. After a restart, old request records return 404.

Profile edits, loading, restoring, saving, and saving as a new profile share one in-flight gate. While the previous request is unfinished, a new profile write returns 409 **before changing settings**. There is no background queue of profile writes. After 30 seconds without confirmation, the request is marked as timed out. New writes remain blocked if a native send is still pending. Reads, stop commands, and file-only imports are not blocked by this gate. Legacy and v1 routes share the same gate; flow-compensation changes also use it.

## Endpoint index

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/status` | Connection, machine state, temperature, flow, pressure, scale, and cached recipe |
| GET / POST | `/api/v1/recipe` | Temporary dose, beverage-weight target, and global temperature adjustments |
| GET / POST | `/api/v1/profile` | Full current profile, steps, and temporary edits |
| POST | `/api/v1/profile/restore` | Reload the current profile file |
| POST | `/api/v1/profile/save` | Save the current profile through de1app and read it back |
| POST | `/api/v1/profile/save-as` | Save under a new name, producing Tcl and JSON profile files |
| GET / POST | `/api/v1/favorites` | Streamline favorite-profile slots |
| GET / POST | `/api/v1/shortcuts` | Streamline dose/yield and temperature presets |
| GET / POST | `/api/v1/settings` | Preheat, automatic sleep, and brightness |
| GET / POST | `/api/v1/controls` | Flush, hot-water, and steam parameters |
| GET / POST | `/api/v1/scale` | Scale state and stop policy |
| POST | `/api/v1/scale/tare` | Tare through the native scale method |
| GET / POST | `/api/v1/scheduler` | Scheduled wake and keep-awake interval |
| GET / POST | `/api/v1/charging` | Smart charging and machine USB power |
| GET / POST | `/api/v1/flow-compensation` | Read existing compensation-plugin details and toggle its configuration |
| GET | `/api/v1/plugins` | Related plugin load/enabled state and HDS status |
| GET | `/api/v1/profiles` | List Tcl profile files |
| POST | `/api/v1/profiles/import` | Validate or import Tcl / v2 JSON without selecting the profile |
| GET / PUT | `/api/v1/profiles/{name.tcl}` | Download or select a profile |
| GET | `/api/v1/shots`, `/api/v1/shots/{name.shot}` | List or download raw shot history |
| GET | `/api/v1/shots/json`, `/api/v1/shots/json/{name.json}` | List or download JSON shot history |
| GET | `/api/v1/requests/{request_id}` | Read the execution record |
| POST | `/api/v1/machine/{wake,sleep,stop}` | Native wake, sleep, or stop |
| POST | `/api/v1/machine/{espresso,flush,steam,hotwater}` | Unavailable; returns 403 start_disabled |
| POST | `/api/v1/grinder/{start,stop}` | Optional bridge to the existing Crystal (小方) grinder plugin; start is unavailable |

Parameter changes generally require a connected machine in `Idle` or `Sleep`; edits are rejected while the machine is running. Remote start endpoints return `403 start_disabled` for espresso, flush, hot water, steam, and grinder starts, regardless of the legacy `allow_start` setting. The dashboard has no start buttons. Remote stop, wake and sleep remain available through native de1app controls.

## Recipe and profile

`POST /api/v1/recipe` accepts any nonempty combination of:

| Field | Unit and range |
|---|---|
| `dose_g` | Coffee dose, 0.1–30 g |
| `yield_g` | Beverage-weight target, 0–2000 g; 0 follows native de1app semantics |
| `temperature_c` | 0–105 °C; shifts step temperatures by the same amount, preserving their differences; rejected if a resulting temperature is out of range |

These are temporary app adjustments and do not overwrite the source profile. The beverage-weight target is synchronized through Streamline's native method. It is not the machine-metered input-water volume.

`GET /api/v1/profile` also includes `editable_steps`, `steps`, `target_volume_ml`, `volume_count_start`, `notes`, and `dirty`. Basic profiles also return read-only `basic_parameters` and `display_steps`. A `display_steps_readback` value of `native_conversion` means the native converter generated the preview from a settings copy, without sending anything to the machine. `unavailable`, `invalid_parameters`, and `empty` indicate an unavailable preview, invalid parameters, or zero phase durations. Basic profiles retain `steps: []` and `editable_steps: false`; these fields do not mean the profile has no content.

The profile-selection PUT response includes a `current_profile` snapshot so clients can correlate its parameters with that request's receipt. The snapshot is not a device acknowledgment.

`POST /api/v1/profile` accepts the recipe fields above plus:

| Field | Meaning and limits |
|---|---|
| `steps` | Complete step array for an advanced profile, 1–20 steps. At most 19 when the native extra preinfusion pause is enabled. Basic profiles do not support step editing. |
| `target_volume_ml` | Machine-metered target volume, 0–2000 mL; distinct from beverage weight on the scale |
| `volume_count_start` | Advanced-profile volume-counting start point; integer from 0 through the number of steps, following native semantics |
| `notes` | Profile notes, at most 10,000 characters |

Each step requires `pump` (`pressure` or `flow`), `sensor` (`coffee` or `water`), `transition` (`fast` or `smooth`), `temperature`, `seconds`, and the `pressure` or `flow` field selected by `pump`.

Optional fields are `name`, `popup`, `volume`, `weight`, `max_flow_or_pressure`, `max_flow_or_pressure_range`, `exit_if`, `exit_type`, and the exit-threshold fields. `name` is limited to 200 characters and `popup` to 1,000 characters.

| Step value | Range |
|---|---|
| Temperature | 0–105 °C |
| Duration | 0–127 s |
| Pressure | 0–12 bar |
| Flow | 0–12 mL/s |
| Step volume | 0–1023 mL |
| Step weight | 0–2000 g |
| `max_flow_or_pressure`, `max_flow_or_pressure_range` | 0–12, in the corresponding flow or pressure units |
| Exit thresholds | 0–12, in bar for pressure or mL/s for flow |

`exit_type` must be `pressure_under`, `pressure_over`, `flow_under`, or `flow_over`. When `exit_if` is enabled, explicitly supply the matching threshold: `exit_pressure_under`, `exit_pressure_over`, `exit_flow_under`, or `exit_flow_over`. If `steps` and `temperature_c` are supplied together, the global temperature must equal the first step's temperature.

`coffee` and `water` select different de1app temperature-sensor control modes and are not interchangeable. A setpoint is not a measured temperature inside the puck. Commanded flow, machine-reported flow, scale weight change, and final beverage weight are also different measurements.

Restore, save, and save-as are separate actions:

| Request | Effect |
|---|---|
| `POST /api/v1/profile/restore` with `{}` | Reselect the current file and discard unsaved current changes. Uses native loading, skin synchronization, and settings persistence. |
| `POST /api/v1/profile/save` with `{}` | Save the current profile. A read-only original returns 409; use save-as. |
| `POST /api/v1/profile/save-as` with `{"filename":"my-profile.tcl","title":"My profile"}` | Save under a new name and make it the current profile. Rejects the operation if either the destination Tcl or JSON file already exists. |

Save-as requires a `.tcl` filename. Saving uses native `save_profile` and checks the resulting Tcl and JSON files. The two files are not written in one atomic operation. On `save_unknown`, read the files to establish the result before considering another request; do not retry blindly. Profiles with executable `advanced_shot_tcl` cannot be edited or selected for execution through this API.

## Local file import

`POST /api/v1/profiles/import` accepts `filename`, `content`, and `format` (`tcl` or `json`), plus optional `dry_run` and `overwrite` booleans, both defaulting to `false`. The filename must identify a single file inside the profile directory. JSON is converted to a Tcl parameter list.

With `dry_run=true`, the endpoint validates without writing a file. An existing filename returns 409 unless `overwrite=true`. The response contains `filename`, `title`, `format`, `saved`, and `readback`. Importing does not select the profile, send Bluetooth commands, or start the machine. The web interface validates the original content before displaying a preview; it does not reserialize JSON in a way that could hide duplicate keys.

Tcl input is a parameter data list, not an executable script. JSON import supports de1app v2 advanced profiles. Unknown or duplicate fields, nonempty temporary-change fields, and semantics that cannot be represented are rejected. Missing dose or beverage-weight values are not filled with invented defaults. Legacy `/api/profile` uploads retain their same-name overwrite behavior.

## Favorites and presets

`POST /api/v1/favorites` accepts:

```json
{"slots":[{"slot":1,"profile":"my-profile"}]}
```

Slots are numbered 1–5. `profile` is a filename without `.tcl`; an empty string clears the slot. Do not repeat a slot or create duplicate profiles or button labels that Streamline cannot support.

`POST /api/v1/shortcuts` accepts:

```json
{"dose_yield":[{"slot":1,"dose_g":18,"yield_g":36}],"temperatures":[{"slot":1,"temperature_c":92}]}
```

Each group has slots 1–4. Either group may be submitted on its own. Dose, yield, and temperature use the recipe ranges above. Updating these slots saves settings; it does not select a profile or start brewing. These endpoints require Streamline's native settings and refresh methods.

## Preheat, automatic sleep, and brightness

`GET /api/v1/settings` reads the settings below. `POST /api/v1/settings` updates a nonempty selection of them.

| Field | Range |
|---|---|
| `preheat_phase1_flow_ml_s` | 0.5–6 mL/s |
| `preheat_phase2_flow_ml_s` | 0.5–8 mL/s |
| `preheat_timeout_s` | 1–30 s |
| `idle_temperature_c` | 0–99 °C, in 0.5 °C steps |
| `sleep_timeout_minutes` | Integer 0–480 minutes; 0 disables automatic sleep |
| `awake_brightness`, `sleep_brightness` | Integer 0–100 percent |

Preheat flow and timeout use 0.1-unit increments. The adapter converts to native internal units. The native preheat setter also resends the existing flush, hot-water, and steam parameters. It does not change the official flow-calibration multiplier.

## Flush, hot water, and steam

`GET /api/v1/controls` reads these settings. `POST /api/v1/controls` updates a nonempty selection.

| Field | Meaning and range |
|---|---|
| `flush_flow_ml_s` | 1–10 mL/s, in 0.1 steps |
| `flush_timeout_s` | 3–120 s, in 0.1 steps |
| `hotwater_flow_ml_s` | 1–10 mL/s, in 0.1 steps |
| `hotwater_temperature_c` | Integer 0–100 °C |
| `hotwater_target` | Integer 3–255; check the returned unit |
| `hotwater_timeout_s` | Integer 1–255 s |
| `water_stop_on_scale` | Whether hot water stops by scale weight |
| `steam_enabled` | Inverse of the native `steam_disabled` setting |
| `steam_flow_ml_s` | 0.4–2.5 mL/s, in 0.01 steps; multiplied by 100 internally |
| `steam_temperature_c` | Integer 135–170 °C |
| `steam_timeout_s` | Integer 0–255 s; 0 is encoded as 255 seconds for the firmware |

The response also reports `hotwater_target_unit`, `hotwater_stop_mode`, `firmware_hotwater_volume_ml`, `target_effective`, and a warning when applicable. With a connected scale and weight-based stopping enabled, the target is a threshold in grams and the firmware volume limit is 250 mL. With a connected scale and weight-based stopping disabled, native code still uses 250 mL and returns `target_effective=false`; the configured volume target must not be treated as effective.

These POST requests set parameters; they do not start water flow. The native steam/hot-water settings bundle may also send existing flush settings and steam high-flow-start settings.

## Scale, scheduling, and charging

### Scale

Read-only fields in `/api/v1/scale` include `connected`, `scale_type`, `weight_g`, `flow_g_s`, and `autotare_states`. The automatic-tare state list cannot be changed through this API.

Writable fields are `require_scale`, `keep_scale_on`, and `stop_before_s` (−1 to 1.5 seconds, in 0.01 steps). Updating these settings does not tare immediately. Use the separate `POST /api/v1/scale/tare` with `{}` to tare.

### Scheduler

Writable fields in `/api/v1/scheduler` are `enabled`, `wake_time`, and `awake_until`. Times use 24-hour `HH:MM` in the tablet's local time zone. When enabled, the end must not be earlier than the start; overnight intervals are unsupported. Equal times mean no keep-awake interval.

`awake_until` is the end of the native keep-awake interval, not a scheduled sleep action. The returned `awake_interval_enabled` means an interval is configured and enabled; it does not mean the current time is inside that interval. `next_wake_at` is the native calculation in Unix seconds and is empty when scheduling is disabled. Saving registers a future wake timer; it does not directly call wake or sleep functions.

### Charging

Writable fields in `/api/v1/charging` are `smart_charging_mode` (`off`, `on`, or `night`) and `machine_usb_enabled`. The mode is a three-way choice, not a boolean.

Changing the mode immediately invokes the native charging policy. An explicit USB request in the same update is applied after that policy. A later periodic policy run can override manual USB state, even in `off` mode. `usb_override_temporary=true` makes this limitation explicit.

## Optional flow compensation

`POST /api/v1/flow-compensation` accepts only `{"enabled":true}` or `{"enabled":false}`. It requires the existing `flow_lut` plugin to be loaded and enabled. If unavailable, GET returns `available=false` and a write returns 501. This endpoint does not expand the compensation scope or change tables, multipliers, or calibration.

Details include target identity, `map_id`, `current_profile_match`, `last_state`, `last_message`, `changes` (containing `target`, `command`, `estimate`, and `stage`), `ack`, `last_profile`, `updated`, and `fallback_reason`.

`current_profile_match` compares only the filename and title; it does not establish that every parameter meets the compensation conditions. `ack_scope=last_published_send` means the acknowledgment belongs to the plugin's last published send record and cannot be attributed to the current edit. Missing acknowledgments remain empty. Estimated flow is not a measurement of actual water output.

## Legacy compatibility

Compatibility routes support existing Advanced REST clients. Use v1 for new clients. Legacy paths accept `?auth=<token>` or a Bearer header, support `download=true`, and allow a trailing slash. A request ID is optional for legacy clients; if supplied, it is checked for duplicates.

| Method | Path | Behavior |
|---|---|---|
| GET | `/`, `/api/help` | Web interface / machine-readable API summary |
| GET / POST | `/api/status` | Basic status / wake or sleep using `active` |
| GET | `/api/status/details` | Legacy detail fields; includes seven sample arrays in `Espresso` state |
| GET / POST | `/api/profile` | List / upload a Tcl parameter list; uploads overwrite the same filename |
| GET / PUT | `/api/profile/{name.tcl}` | Download / select |
| GET | `/api/shot`, `/api/shot/{name.shot}` | Raw shot history |
| GET / PUT | `/api/v2/shot/{timestamp}` | JSON history / DYE “use as next shot” |
| GET | `/api/v2/shots` | SDB summaries; returns 501 if the dependency is not enabled |
| GET | `/api/flush` | **Flush the log buffer. This does not start a water flush.** |

Legacy upload bodies are UTF-8 Tcl data lists. The `filename` header supplies the `.tcl` filename; Chinese filenames may be URL-encoded. Paths outside the allowed directory, symbolic links, executable profile scripts, and settings outside the profile are rejected.

DYE and SDB use their existing plugins. If a dependency is missing, Decent Remote does not copy its database or invent history fields. The optional Crystal grinder bridge calls the existing control chain and returns 501 when the plugin is unavailable; the web interface does not include a grinder control.
