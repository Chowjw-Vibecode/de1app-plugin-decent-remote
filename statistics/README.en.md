# Decent tools usage by country

[中文](README.md)

Installation totals grouped by country or region cover Decent Remote and This Cup, with an all-products view and separate categories. A random installation ID prevents double-counting within each product. Names, accounts, access keys, profiles and shot records are not sent.

**The Cloudflare Worker and D1 database are deployed. Version 0.3.4 includes the service URL.** [Public summary](https://chowjw-vibecode.github.io/usage-stats/).

That deployment is the original v1 service. The category update requires the database migration, Worker deployment and page update below. Local source and previews do not establish deployment.

Service: `https://decent-remote-usage.decent-remote-stats.workers.dev`; [country summary](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary). Deployment checks covered creation, deduplication, validation, deletion and summary export. See [VALIDATION.md](../docs/VALIDATION.md) for the verification scope.

## Data flow

`Random installation ID → Cloudflare Worker → D1 → Public summary → GitHub Pages`

- The tablet stores a random ID and the last attempt and success times. Successful updates are seven days apart; failed attempts wait at least 24 hours before retrying.
- D1 stores the ID's SHA-256 hash, product, country, and first and latest update times. Existing records and older clients without a product are `decent_remote`; This Cup is `this_cup`. These identify an installation record, not an account or hardware identity.
- The GitHub page contains country totals, 30-day active-installation counts and the summary time, without installation records.
- Cloudflare infers country from the request. VPNs, reinstalls and fabricated requests can affect the numbers; they are not counts of people. The application does not retain raw IP addresses in its database or logs. Cloudflare processes network information to handle requests.
- An empty endpoint produces no traffic. The client uses a background thread and skips updates if dependencies are unavailable. It does not control the machine. Configuration-based disabling is documented in `docs/USAGE.md` in the install package.
- The thread and settings above belong to the classic de1app client. This Cup sends only its random ID and product from its browser, without credentials. Clearing browser storage, using another browser or changing the page origin can create another installation. Counts are neither people nor physical devices.

## API

| Method and path | Purpose |
| --- | --- |
| `POST /v1/check-in` | Accepts `{"install_id":"32 lowercase hexadecimal characters","product":"this_cup"}`; product is optional and defaults to `decent_remote`. Only these two products are accepted |
| `DELETE /v1/check-in` | The same body deletes only the installation in that product; omitting product preserves legacy deletion. Repeated deletion is safe |
| `GET /v1/summary` | Original schema 1 and meaning: Decent Remote country totals and 30-day active counts only |
| `GET /v2/summary` | Schema 2: combined totals plus `products`, always containing both categories, including zero-installation categories |
| `OPTIONS /v1/check-in` | Browser preflight permitting POST, DELETE and Content-Type; no database write or credentials |

`countries` is always `[{"country":"CN","installations":integer,"active_30d":integer}]`. Each v2 product contains `product`, `total_installations`, `active_30d` and `countries`; top-level counts reconcile to the sum of products. `generated_at` and `scope` retain their original definitions. POST success remains `{"accepted":true,"next_check_in_after_s":604800}`.

Responses permit anonymous cross-origin access with `Access-Control-Allow-Origin: *` and no Allow-Credentials. Location comes only from Cloudflare; client country, IP or device fields are rejected. Legacy hashes remain unchanged; new products use product-prefixed hashes to keep updates and deletions separate.

Server receipt time determines which update is newer. An older request cannot overwrite a newer country, ties keep the existing country, and first-seen time keeps the earliest value. The random ID also authorizes deletion of its record; keep it out of public logs.

## Local checks

From the source bundle root, with Node.js 22.13+, Tcl 8.6/Tcllib and Python 3.10+:

```sh
node --test statistics/tests/worker.test.mjs
tclsh8.6 statistics/tests/client.test.tcl
python3 statistics/tests/export.test.py
node --test statistics/tests/site.test.mjs
```

Tests use an in-memory SQLite database and simulated transport. They do not contact a live service. The native client also requires Tcl Thread, TclCurl and de1app's `allcerts.pem` trust store.

The page check uses Playwright and a local synthetic fixture, without a device or live statistics request. To generate a labeled preview and screenshots:

```sh
USAGE_SCREENSHOT_DIR=statistics/QA证据/product-preview node --test statistics/tests/site.test.mjs
python3 -m http.server 8897 --bind 127.0.0.1 --directory statistics/QA证据/product-preview
```

Open `http://127.0.0.1:8897/`. Its numbers come from `tests/fixtures/products-summary.json`, not real installations.

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

### Upgrade an existing v1 service

From `statistics/`, capture the v1 aggregate, apply the migration first, then deploy the Worker. `migrations/0001_products.sql` is only for an existing v1 database without a `product` column. A new database uses the current `schema.sql` above and must not then run this upgrade migration. Wrangler tracks applied migrations, so rerunning the migration command does not apply them twice.

```sh
curl --fail --silent --show-error https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary
npx wrangler d1 migrations list decent-remote-usage --remote
npx wrangler d1 migrations apply decent-remote-usage --remote
npx wrangler d1 execute decent-remote-usage --remote --command "SELECT product,COUNT(*) AS installations FROM installations GROUP BY product"
npx wrangler deploy
curl --fail --silent --show-error https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary
curl --fail --silent --show-error https://decent-remote-usage.decent-remote-stats.workers.dev/v2/summary
curl --silent --show-error --include --request OPTIONS --header 'Origin: http://localhost:8080' --header 'Access-Control-Request-Method: POST' --header 'Access-Control-Request-Headers: content-type' https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in
```

Confirm the old installation total is unchanged, v2's Decent Remote category equals v1, This Cup is zero before new reports, and preflight returns 204. Never publish installation records. Then publish the page and browser client. A failed export leaves the existing page available. Once This Cup records exist, do not restore the original category-unaware Worker: its v1 summary would include both products. Any rollback version must retain the v1 product filter and added column; do not delete records or restore an older database wholesale.

## GitHub summary page

Enable Pages with GitHub Actions as its source. `USAGE_SUMMARY_URL` may retain the original `https://HOST/v1/summary` or use `/v2/summary`; the workflow's `--products` explicitly selects `/v2/summary` on that host and requires a product summary. Run the `Usage by country` workflow; it then updates daily.

The workflow reads only public aggregates, validates fields, types and product/country totals, and publishes `statistics/site/`. Failed fetches or invalid summaries leave the existing published page in place. An empty repository variable skips deployment. The page supports English, Chinese and All products / Decent Remote / This Cup. It loads no external fonts or analytics scripts. The included `data.json` retains the existing production snapshot. For legacy snapshots, the page explains that only Decent Remote is covered; This Cup shows unavailable rather than a misleading zero.

References: [Cloudflare request metadata](https://developers.cloudflare.com/workers/runtime-apis/request/), [D1](https://developers.cloudflare.com/d1/), [rate-limit bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [GitHub Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
