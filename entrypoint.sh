#!/bin/sh

echo "run_id: $RUN_ID in $ENVIRONMENT"
# echo "HTTP_PROXY: $HTTP_PROXY"

if nc -z localhost 3128; then
  echo "✅ Port 3188 is open on localhost"
else
  echo "❌ Port 3188 is closed or unreachable on localhost"
  exit 1
fi

NOW=$(date +"%Y%m%d-%H%M%S")

if [ -z "${JM_HOME}" ]; then
  JM_HOME=/opt/perftest
fi

JM_SCENARIOS=${JM_HOME}/scenarios
JM_REPORTS=${JM_HOME}/reports
JM_LOGS=${JM_HOME}/logs

mkdir -p ${JM_REPORTS} ${JM_LOGS}

SCENARIOFILE=${JM_SCENARIOS}/${TEST_SCENARIO}.jmx
REPORTFILE=${NOW}-perftest-${TEST_SCENARIO}-report.csv
LOGFILE=${JM_LOGS}/perftest-${TEST_SCENARIO}.log

# Run the test suite
# export HTTP_PROXY=http://localhost:3128
# jmeter -n -t ${SCENARIOFILE} -e -l "${REPORTFILE}" -o ${JM_REPORTS} -j ${LOGFILE} -f -Jenv="${ENVIRONMENT}"
# test_exit_code=$?
# jmeter -n -t ${SCENARIOFILE} -e -l "${REPORTFILE}" -o ${JM_REPORTS} -j ${LOGFILE} -f -Jenv="${ENVIRONMENT}" -JproxyHost="localhost" -JproxyPort="3128" -JproxyScheme="http"; test_exit_code=$?
# jmeter -n \
#   -t "${SCENARIOFILE}" \
#   -JproxyHost=localhost \
#   -JproxyPort=3128 \
#   -JproxyScheme=http \
#   -Jenv="${ENVIRONMENT}" \
#   -l "${RESULTFILE}" \
#   -j "${LOGFILE}" \
#   -o "${HTML_REPORT_DIR}" \
#   -e \
#   -f
jmeter -n \
  -t "${SCENARIOFILE}" \
  -e \
  -l "${REPORTFILE}" \
  -o "${JM_REPORTS}" \
  -j "${LOGFILE}" \
  -f \
  -Jenv="${ENVIRONMENT}" \
  -Dhttp.proxyHost=localhost \
  -Dhttp.proxyPort=3128 \
  -Dhttps.proxyHost=localhost \
  -Dhttps.proxyPort=3128 \
  -Dhttp.nonProxyHosts="localhost|127.0.0.1"
# jmeter -n -t test.jmx -JproxyHost=${__P(proxyHost)} -JproxyPort=${__P(proxyPort)} -JproxyScheme=${__P(proxyScheme)} -e -l "${REPORTFILE}" -o ${JM_REPORTS} -j ${LOGFILE} -f -Jenv="${ENVIRONMENT}"
# jmeter -n -t ${SCENARIOFILE} -JproxyHost="${proxyHost}" -JproxyPort="${proxyPort}" -JproxyScheme="${proxyScheme}" -Jenv="${ENVIRONMENT}" -l "${REPORTFILE}" -j "${LOGFILE}" -o "${JM_REPORTS}" -e -f; test_exit_code=$?

# Publish the results into S3 so they can be displayed in the CDP Portal
if [ -n "$RESULTS_OUTPUT_S3_PATH" ]; then
  # Copy the CSV report file and the generated report files to the S3 bucket
   if [ -f "$JM_REPORTS/index.html" ]; then
      aws --endpoint-url=$S3_ENDPOINT s3 cp "$REPORTFILE" "$RESULTS_OUTPUT_S3_PATH/$REPORTFILE"
      aws --endpoint-url=$S3_ENDPOINT s3 cp "$JM_REPORTS" "$RESULTS_OUTPUT_S3_PATH" --recursive
      if [ $? -eq 0 ]; then
        echo "CSV report file and test results published to $RESULTS_OUTPUT_S3_PATH"
      fi
   else
      echo "$JM_REPORTS/index.html is not found"
      exit 1
   fi
else
   echo "RESULTS_OUTPUT_S3_PATH is not set"
   exit 1
fi

exit $test_exit_code
