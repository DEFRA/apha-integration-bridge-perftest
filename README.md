# APHA Integration Bridge JMeter Boundary Test

This repo is a portable `performance/jmeter` pack for the APHA Integration Bridge boundary test.

It contains:

- `apha-integration-bridge-boundary.jmx`: the JMeter plan
- `environments/perf-test.properties`: the perf-test property file
- `bridge-perf`: the main runner
- `entrypoint.sh`: container/CDP entrypoint
- `secrets.env.example`: example local secrets file

## Run It

Run the full perf-test boundary test:

```bash
./bridge-perf
```

Open the same plan in the JMeter GUI:

```bash
./bridge-perf gui
```

Pass extra JMeter args after `--`:

```bash
./bridge-perf -- -Jtarget.total.rps=30
./bridge-perf gui -- -Jresults.jtl=results/perf-test-boundary.jtl
```

There are matching `make` targets:

```bash
make perf-test
make gui
```

## Secrets

`bridge-perf` loads local env files from this folder in this order:

- `secrets.env`
- `.env`
- `.env.local`
- `.envrc`

It accepts both `KEY=value` and `export KEY=value`.

Existing shell environment variables win over file values.

For normal runs it automatically injects `-Jauth.client_secret` from `PERF_SECRET`.

If you pass `-Jauth.client_secret=...` explicitly, that value is used instead.

The OAuth token setup step uses its own retry and timeout settings from `environments/perf-test.properties`, so short-lived Cognito/network blips are less likely to fail the whole run before the API samplers start.

If CDP cannot reliably reach the Cognito token endpoint, you can set `PERF_BEARER_TOKEN` (or `AUTH_BEARER_TOKEN`) and `bridge-perf` will automatically switch to `auth.mode=bearer_token` for that run. Explicit `-Jauth.*` flags still win over the env-based defaults.

Auth env var support:

- `PERF_SECRET`: default perf-test client secret
- `CLIENT_SECRET`: fallback only if the env-specific secret such as `PERF_SECRET` is not present
- `COGNITO_CLIENT_ID`: optional client ID override
- `COGNITO_CLIENT_SECRET`: optional client secret override
- `COGNITO_DOMAIN`: optional Cognito domain override
- `AUTH_DEBUG=true`: logs resolved auth details with a masked client ID and secret length only

Proxy behavior:

- If `IS_LOCAL=true`, the token fetch does not use a proxy.
- Otherwise, if `HTTPS_PROXY` or `HTTP_PROXY` is set, the Cognito token request uses that proxy.

To set up local secrets, start from:

- [secrets.env.example](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/secrets.env.example)

## Docker / CDP

The Docker image uses:

- [Dockerfile](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/Dockerfile)
- [entrypoint.sh](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/entrypoint.sh)

`entrypoint.sh` always runs the perf-test profile, ignores any non-`perf-test` environment value, and publishes results if `RESULTS_OUTPUT_S3_PATH` is set. The JTL file is uploaded into that S3 prefix, and the generated HTML report contents are uploaded directly into the same prefix so the portal can find `index.html` at the report root.

The report root now contains a lightweight summary landing page, plus:

- `jmeter-dashboard/index.html`: the full stock JMeter dashboard
- `summary.txt`: a plain-text summary of the run
- `sampler-breakdown.tsv`: per-sampler counts and latency figures
- `failure-breakdown.tsv`: grouped failure counts by sampler, response code, and message

After publishing, `entrypoint.sh` exits non-zero if the JTL contains any failed samples, so CDP can mark the run as failed even when JMeter itself exits `0`.
