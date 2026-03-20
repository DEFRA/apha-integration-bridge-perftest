# APHA Integration Bridge JMeter Boundary Test

This repository root contains the complete JMeter boundary test pack. Everything needed to run the boundary test now lives at the top level of the repo, so this directory can be treated as the `performance/jmeter` folder when you copy it into another repository.

It contains a reusable JMeter boundary test plan for 5 safe-load APHA Integration Bridge endpoints already covered by the journey suite:

- `POST /locations/find`
- `GET /workorders`
- `POST /workorders/find`
- `POST /customers/find`
- `POST /organisations/find`

The plan is designed for a controlled 10-minute boundary run at the agreed `25 RPS` steady-state rate with support for bursts up to `50` requests. Setup time is not included in that 10-minute window, and ramp-up is added on top of it. It is not a stress, spike, or soak test.

The CDP default limit of `100 req/s` with `200` burst is intentionally not treated as the expected capacity target for this service.

## Files

- `apha-integration-bridge-boundary.jmx`: main JMeter test plan
- `apha-integration-bridge-boundary.sample.properties`: sample environment/property file
- `environments/`: self-contained environment property templates
- `bridge-perf`: one-command wrapper for GUI, smoke, and boundary runs
- `Makefile`: short aliases for common commands
- `run-boundary.sh`: local wrapper that always runs the JMX from the repository root
- `secrets.env`: optional local secrets file for portable auth values
- `secrets.env.example`: placeholder template for local secrets
- `results/`: default JTL output location

## How Environment Values Work

The test plan is fully property-driven with `__P(...)` so the same `.jmx` can run unchanged in dev, test, and preprod.

The properties in this repository include:

- API protocol, host, and optional port
- Auth mode, token endpoint, client credentials, or bearer token
- Common headers
- Endpoint paths
- Endpoint-specific IDs, query parameters, and POST bodies
- Boundary target RPS and burst ceiling
- Max request duration assertion and HTTP read timeout
- Ramp-up duration
- Thread headroom
- Environment name
- JTL output path

Recommended workflow:

1. Use one of the files in `environments/` as your starting point, or copy `apha-integration-bridge-boundary.sample.properties`.
2. Put local client secrets in `secrets.env` if you want this folder to run after copy/paste without depending on parent shell variables.
3. Replace any data values that are not valid in that environment.
4. Keep the `.jmx` unchanged and override only with `-q` or `-J`.

## Local Secrets

Both `bridge-perf` and `run-boundary.sh` auto-load env files from this directory in the following order:

- `secrets.env`
- `.env`
- `.env.local`
- `.envrc`

They accept both `KEY=value` and `export KEY=value`. Existing shell environment values win, so local files only fill in values that are not already defined. The wrappers automatically inject `-Jauth.client_secret` for `dev`, `test`, `perf-test`, and `preprod`, and `PROD_SECRET` is accepted as a fallback alias for `PREPROD_SECRET`.

That means this folder can carry its own `secrets.env` and be moved into another repo without relying on parent-shell exports.

Keep the repository root in this structure:

```text
.
├── README.md
├── Makefile
├── apha-integration-bridge-boundary.jmx
├── apha-integration-bridge-boundary.sample.properties
├── bridge-perf
├── secrets.env
├── secrets.env.example
├── environments/
├── results/
└── run-boundary.sh
```

## Load Model

The test uses:

- a `setUp Thread Group` to calculate request rates and obtain a bearer token once per run
- a main `Thread Group` with a short ramp-up plus a 10-minute steady-state duration
- a per-endpoint Groovy pacing timer so request rate is throughput-led rather than thread-led
- a global duration assertion so requests explicitly fail if they exceed `10` seconds by default

The request mix is controlled by weights:

- each endpoint gets `target.total.rps * endpoint_weight / sum(all_weights)`
- default weights are even across the 5 endpoints
- default boundary settings are `target.total.rps=25`, `target.burst.requests=50`, and `threads.max=50`
- default latency guardrails are `request.max.duration.ms=10000` and `http.response.timeout.ms=10000`

By default the pack uses `ramp_up.seconds=60` and `test.duration.seconds=600`, so the main load runs for about 11 minutes wall-clock after setup: 1 minute ramp-up plus 10 minutes at the boundary rate.

Boundary mode is intentionally capped at the agreed service limit. If you go above `25 RPS` or above a `50` request burst ceiling, set `-Jtest.mode=stress` explicitly so higher-rate runs are clearly separated from expected steady-state performance.

## Quick Commands

These are the easiest ways to use the pack.

Open the GUI for dev:

```bash
./bridge-perf gui dev
```

Run a low-risk 1-minute dev smoke:

```bash
./bridge-perf smoke dev
```

That smoke run keeps a 60-second steady-state window after a 15-second ramp-up.

Run the full 10-minute dev boundary test:

```bash
./bridge-perf boundary dev
```

Run the full 10-minute test boundary:

```bash
./bridge-perf boundary test
```

There are also short `make` aliases:

```bash
make gui-dev
make smoke-dev
make boundary-dev
make boundary-test
```

The `make` commands set `BRIDGE_PERF_AUTO_INSTALL_JAVA=1`, so if Java 21 or 17 is missing and Homebrew is available, they will try to install `temurin@21` first.

The wrapper will:

- pick the matching file from `environments/`
- auto-load `secrets.env`, `.env`, `.env.local`, and `.envrc` from this directory
- inject `DEV_SECRET`, `TEST_SECRET`, `PERF_SECRET`, or `PREPROD_SECRET` automatically if present
- use `PROD_SECRET` as a fallback for `preprod`
- keep an explicit `-Jauth.client_secret=...` override untouched
- auto-select Java 21 or 17 if one is already installed
- `make` targets can auto-install Temurin 21 with Homebrew when no compatible Java is present

Pass extra JMeter overrides after `--`, for example:

```bash
./bridge-perf smoke dev -- -Jendpoint.locations_find.page_size=25
./bridge-perf run ./environments/test.properties -- -Jtest.mode=stress -Jtarget.total.rps=30 -Jtarget.burst.requests=50
```

## Non-GUI Run Commands

All commands below assume your shell is in the repository root.

Run with the wrapper script:

```bash
./run-boundary.sh ./environments/dev.properties
```

Run directly with JMeter and a local property file:

```bash
jmeter -n \
  -t apha-integration-bridge-boundary.jmx \
  -q environments/dev.properties
```

Run in dev with direct overrides:

```bash
jmeter -n \
  -t apha-integration-bridge-boundary.jmx \
  -q environments/dev.properties \
  -Jenvironment.name=dev \
  -Jauth.client_secret="$DEV_SECRET" \
  -Jresults.jtl=results/dev-boundary.jtl
```

Run in test:

```bash
./run-boundary.sh ./environments/test.properties \
  -Jauth.client_secret="$TEST_SECRET"
```

Run in preprod or perf-test style environments:

```bash
./run-boundary.sh ./environments/preprod.properties \
  -Jauth.client_secret="$PREPROD_SECRET" \
  -Jresults.jtl=results/preprod-boundary.jtl
```

Run in perf-test:

```bash
./run-boundary.sh ./environments/perf-test.properties \
  -Jauth.client_secret="$PERF_SECRET" \
  -Jresults.jtl=results/perf-test-boundary.jtl
```

If you already have a bearer token and do not want JMeter to fetch one:

```bash
jmeter -n \
  -t apha-integration-bridge-boundary.jmx \
  -q environments/dev.properties \
  -Jauth.mode=bearer_token \
  -Jauth.bearer_token="$APHA_BEARER_TOKEN"
```

## Change the Target Rate

Change the total boundary rate with:

```bash
-Jtarget.total.rps=<agreed_safe_rps>
```

Example:

```bash
-Jtarget.total.rps=25
-Jtarget.burst.requests=50
```

To change the mix as well, override one or more weights:

```bash
-Jthroughput.weight.workorders=2
-Jthroughput.weight.organisations_find=0.5
```

## CLI / CI Notes

- The plan writes results to the JTL path in `results.jtl`.
- `bridge-perf` is the recommended entrypoint for day-to-day local use.
- `run-boundary.sh` resolves the test plan and default environment relative to the repository root layout shown above.
- The sample JTL listener is suitable for non-GUI and CI/CD runs.
- Add `-e -o <dashboard_dir>` if you want the standard JMeter HTML dashboard.
- Keep test data valid for the target environment, especially workorder, customer, organisation, and location-search IDs.
- Runs above `25 RPS` must be treated as stress tests and should be launched with `-Jtest.mode=stress`.
- By default, any sampler over 10 seconds fails via both `request.max.duration.ms` and the 10 second HTTP response timeout.
