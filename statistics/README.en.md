# Decent Remote usage by country

[中文](README.md)

Installation totals grouped by country or region help us understand where Decent Remote is used. A random installation ID prevents double-counting. Names, accounts, access keys, profiles and shot records are not sent.

**The Cloudflare Worker and D1 database are deployed. Version 0.3.4 includes the service URL.** [Public summary](https://chowjw-vibecode.github.io/de1app-plugin-decent-remote/).

Service: `https://decent-remote-usage.decent-remote-stats.workers.dev`; [country summary](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary). Deployment checks covered creation, deduplication, validation, deletion and summary export. See [VALIDATION.md](../docs/VALIDATION.md) for the verification scope.

## Data flow

`Random installation ID → Cloudflare Worker → D1 → Public summary → GitHub Pages`

- The tablet stores a random ID and the last attempt and success times. Successful updates are seven days apart; failed attempts wait at least 24 hours before retrying.
- D1 stores the ID's SHA-256 hash, country, and first and latest update times. These identify an installation record, not an account or hardware identity.
- The GitHub page contains country totals, 30-day active-installation counts and the summary time, without installation records.
- Cloudflare infers country from the request. VPNs, reinstalls and fabricated requests can affect the numbers; they are not counts of people. The application does not retain raw IP addresses in its database or logs. Cloudflare processes network information to handle requests.
- An empty endpoint produces no traffic. The client uses a background thread and skips updates if dependencies are unavailable. It does not control the machine. Configuration-based disabling is documented in `docs/USAGE.md` in the install package.

## API

| Method and path | Purpose |
| --- | --- |
| `POST /v1/check-in` | Accepts only `{"install_id":"32 lowercase hexadecimal characters"}`; repeated updates affect the same installation |
| `DELETE /v1/check-in` | The same body deletes that installation; repeated deletion is safe |
| `GET /v1/summary` | Country totals and 30-day active counts, without identifiers |

Server receipt time determines which update is newer. An older request cannot overwrite a newer country, ties keep the existing country, and first-seen time keeps the earliest value. The random ID also authorizes deletion of its record; keep it out of public logs.

## Local checks

From the source bundle root, with Node.js 22.13+, Tcl 8.6/Tcllib and Python 3.10+:

```sh
node --test statistics/tests/worker.test.mjs
tclsh8.6 statistics/tests/client.test.tcl
python3 statistics/tests/export.test.py
```

Tests use an in-memory SQLite database and simulated transport. They do not contact a live service. The native client also requires Tcl Thread, TclCurl and de1app's `allcerts.pem` trust store.

## Cloudflare setup

These are owner-operated deployment steps. Building an archive does not execute them.

1. In `statistics/`, copy `wrangler.example.toml` to `wrangler.toml`.
2. Create a D1 database in your Cloudflare account and add its ID to the local configuration. Choose a rate-limit `namespace_id` not already used by that account.
3. Apply the schema and deploy the Worker:

```sh
npx wrangler d1 create decent-remote-usage
npx wrangler d1 execute decent-remote-usage --remote --file=schema.sql
npx wrangler deploy
```

4. Check the actual HTTPS `/v1/summary` endpoint with a test ID, including creation, deduplication and deletion. Once verified, the publisher replaces the `usage_endpoint` default in `plugin.tcl` with the production `https://HOST/v1/check-in` URL and rebuilds both archives. Fresh installations then use that address automatically; users do not need to configure it individually. Existing configured addresses are preserved. Test devices that already saved an empty endpoint need that setting updated separately. Never distribute Cloudflare or GitHub administration tokens with the plugin.

The example disables Worker observability logs. Rate limits use shared route keys, not IP addresses or installation IDs. Cloudflare enforces approximate per-edge limits; these are not global spending caps or proof of genuine installations.

## GitHub summary page

Enable Pages with GitHub Actions as its source. Set the repository variable `USAGE_SUMMARY_URL` to the deployed `https://HOST/v1/summary` endpoint. Run the `Usage by country` workflow; it then updates daily.

The workflow reads only public aggregates, validates their fields, types and totals, and publishes `statistics/site/`. Failed fetches or invalid summaries leave the existing published page in place. An empty repository variable skips deployment. The page supports English and Chinese and loads no external fonts or analytics scripts. The included `data.json` is a snapshot exported from the deployed service, not a continuously updated online page.

References: [Cloudflare request metadata](https://developers.cloudflare.com/workers/runtime-apis/request/), [D1](https://developers.cloudflare.com/d1/), [rate-limit bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [GitHub Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
