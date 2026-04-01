#!/bin/sh
# entrypoint.sh
set -u   # no -e so we still publish after test failures

echo "[entrypoint] run_id: ${RUN_ID:-unset}"

ENV_VALUE="${ENV_NAME:-${environment:-${ENVIRONMENT:-perf-test}}}"
if [ "${ENV_VALUE}" != "perf-test" ]; then
  echo "[entrypoint] ignoring requested environment '${ENV_VALUE}' and using 'perf-test'"
fi
export environment="perf-test"
export ENV_NAME="perf-test"
echo "[entrypoint] environment: perf-test"

if [ -n "${PERF_BEARER_TOKEN:-${AUTH_BEARER_TOKEN:-}}" ]; then
  echo "[entrypoint] auth mode: bearer_token (from environment)"
else
  echo "[entrypoint] auth mode: client_credentials"
fi

NOW="$(date +"%Y%m%d-%H%M%S")"
RUN_LABEL="${RUN_ID:-${NOW}}"
RESULTS_DIR="./results"
REPORTS_BASE="./reports"
REPORT_NAME="${RUN_LABEL}-perf-test-boundary"
RESULT_FILE="${RESULTS_DIR}/${REPORT_NAME}.jtl"
REPORT_DIR="${REPORTS_BASE}/${REPORT_NAME}"
DASHBOARD_DIR="${REPORT_DIR}/jmeter-dashboard"

mkdir -p "${RESULTS_DIR}" "${REPORTS_BASE}" "${REPORT_DIR}"

echo "[entrypoint] running boundary test: environment=perf-test"
./bridge-perf -- \
  -Jresults.jtl=/dev/null \
  -l "${RESULT_FILE}" \
  -e -o "${DASHBOARD_DIR}"
test_exit=$?
echo "[entrypoint] bridge-perf exit code: ${test_exit}"

if ./report-summary.sh "${RESULT_FILE}" "${REPORT_DIR}" "${RUN_LABEL}" "jmeter-dashboard/index.html"; then
  echo "[entrypoint] generated summary report landing page"
else
  echo "[entrypoint] failed to generate summary report landing page"
fi

failure_count=0
if [ -f "${RESULT_FILE}" ]; then
  failure_count="$(grep -c ',false,' "${RESULT_FILE}" || true)"
fi
echo "[entrypoint] failed sample count: ${failure_count}"

echo "[entrypoint] publishing results..."
publish_exit=0
if [ -n "${RESULTS_OUTPUT_S3_PATH:-}" ]; then
  if [ -f "${RESULT_FILE}" ]; then
    aws --endpoint-url="${S3_ENDPOINT}" s3 cp "${RESULT_FILE}" "${RESULTS_OUTPUT_S3_PATH}/$(basename "${RESULT_FILE}")" || publish_exit=$?
  fi

  if [ "${publish_exit}" -eq 0 ] && [ -f "${REPORT_DIR}/index.html" ]; then
    aws --endpoint-url="${S3_ENDPOINT}" s3 cp "${REPORT_DIR}/" "${RESULTS_OUTPUT_S3_PATH}/" --recursive || publish_exit=$?
  elif [ "${publish_exit}" -eq 0 ]; then
    echo "[entrypoint] report index not found at ${REPORT_DIR}/index.html; skipping report upload"
  fi
else
  echo "[entrypoint] RESULTS_OUTPUT_S3_PATH is not set; skipping publish"
fi
echo "[entrypoint] publish exit code: ${publish_exit}"

ls -lah "${REPORT_DIR}" || true

if [ "${publish_exit}" -ne 0 ]; then
  echo "[entrypoint] failed to publish test results"
  exit "${publish_exit}"
fi

run_exit="${test_exit}"
if [ "${run_exit}" -eq 0 ] && [ "${failure_count}" -gt 0 ]; then
  run_exit=1
fi

echo "[entrypoint] test suite complete (bridge-perf exit ${test_exit}, final exit ${run_exit})"
exit "${run_exit}"
