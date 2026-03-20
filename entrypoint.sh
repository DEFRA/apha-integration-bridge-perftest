#!/bin/sh
# entrypoint.sh
set -u   # no -e so we still publish after test failures

echo "[entrypoint] run_id: ${RUN_ID:-unset}"

ENV_VALUE="${environment:-${ENVIRONMENT:-dev}}"
export environment="${ENV_VALUE}"
echo "[entrypoint] environment: ${ENV_VALUE}"

JMETER_ENV="${ENV_VALUE}"
if [ "${ENV_VALUE}" = "prod" ]; then
  JMETER_ENV="preprod"
  echo "[entrypoint] mapping environment 'prod' to '${JMETER_ENV}' for JMeter properties"
fi

NOW="$(date +"%Y%m%d-%H%M%S")"
RUN_LABEL="${RUN_ID:-${NOW}}"
RESULTS_DIR="./results"
REPORTS_BASE="./reports"
REPORT_NAME="${RUN_LABEL}-${ENV_VALUE}-boundary"
RESULT_FILE="${RESULTS_DIR}/${REPORT_NAME}.jtl"
REPORT_DIR="${REPORTS_BASE}/${REPORT_NAME}"

mkdir -p "${RESULTS_DIR}" "${REPORTS_BASE}"

echo "[entrypoint] running boundary test: environment=${ENV_VALUE}"
./bridge-perf run "./environments/${JMETER_ENV}.properties" -- \
  -Jresults.jtl=/dev/null \
  -l "${RESULT_FILE}" \
  -e -o "${REPORT_DIR}"
test_exit=$?
echo "[entrypoint] bridge-perf exit code: ${test_exit}"

echo "[entrypoint] publishing results..."
publish_exit=0
if [ -n "${RESULTS_OUTPUT_S3_PATH:-}" ]; then
  if [ -f "${RESULT_FILE}" ]; then
    aws --endpoint-url="${S3_ENDPOINT}" s3 cp "${RESULT_FILE}" "${RESULTS_OUTPUT_S3_PATH}/$(basename "${RESULT_FILE}")" || publish_exit=$?
  fi

  if [ "${publish_exit}" -eq 0 ] && [ -f "${REPORT_DIR}/index.html" ]; then
    aws --endpoint-url="${S3_ENDPOINT}" s3 cp "${REPORT_DIR}" "${RESULTS_OUTPUT_S3_PATH}/$(basename "${REPORT_DIR}")" --recursive || publish_exit=$?
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

echo "[entrypoint] test suite complete (bridge-perf exit ${test_exit})"
exit "${test_exit}"
