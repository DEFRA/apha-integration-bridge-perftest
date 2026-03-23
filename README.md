# APHA Integration Bridge JMeter Boundary Test

This repo is a portable `performance/jmeter` pack for the APHA Integration Bridge boundary test.

It contains:

- `apha-integration-bridge-boundary.jmx`: the JMeter plan
- `environments/`: per-environment property files
- `bridge-perf`: the main runner
- `entrypoint.sh`: container/CDP entrypoint
- `secrets.env.example`: example local secrets file

## Run It

Run the full boundary test for an environment:

```bash
./bridge-perf dev
./bridge-perf test
./bridge-perf perf-test
./bridge-perf preprod
```

Open the same plan in the JMeter GUI:

```bash
./bridge-perf gui dev
./bridge-perf gui test
```

Pass extra JMeter args after `--`:

```bash
./bridge-perf dev -- -Jtarget.total.rps=30
./bridge-perf preprod -- -Jresults.jtl=results/preprod-boundary.jtl
```

There are matching `make` targets:

```bash
make dev
make test
make perf-test
make preprod
make gui-dev
make gui-test
make gui-perf-test
make gui-preprod
```

## Secrets

`bridge-perf` loads local env files from this folder in this order:

- `secrets.env`
- `.env`
- `.env.local`
- `.envrc`

It accepts both `KEY=value` and `export KEY=value`.

Existing shell environment variables win over file values.

For normal runs it automatically injects `-Jauth.client_secret` for:

- `dev` via `DEV_SECRET`
- `test` via `TEST_SECRET`
- `perf-test` via `PERF_SECRET`
- `preprod` via `PREPROD_SECRET` or `PROD_SECRET`

If you pass `-Jauth.client_secret=...` explicitly, that value is used instead.

To set up local secrets, start from:

- [secrets.env.example](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/secrets.env.example)

## Docker / CDP

The Docker image uses:

- [Dockerfile](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/Dockerfile)
- [entrypoint.sh](/Users/eoincorr/Documents/DEFRA/apha-integration-bridge-perftest/entrypoint.sh)

`entrypoint.sh` reads `ENVIRONMENT`, maps `prod` to `preprod`, runs `bridge-perf`, and publishes results if `RESULTS_OUTPUT_S3_PATH` is set.
