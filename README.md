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

To set up local secrets, start from:

- [secrets.env.example](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/secrets.env.example)

## Docker / CDP

The Docker image uses:

- [Dockerfile](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/Dockerfile)
- [entrypoint.sh](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/entrypoint.sh)

`entrypoint.sh` always runs the perf-test profile, ignores any non-`perf-test` environment value, and publishes results if `RESULTS_OUTPUT_S3_PATH` is set.
