#!/bin/sh

set -eu

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <results.jtl> <report-dir> <run-label> [dashboard-relative-path]" >&2
  exit 1
fi

RESULT_FILE="$1"
REPORT_DIR="$2"
RUN_LABEL="$3"
DASHBOARD_RELATIVE_PATH="${4:-jmeter-dashboard/index.html}"

if [ ! -f "${RESULT_FILE}" ]; then
  echo "Result file not found: ${RESULT_FILE}" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/report-summary.XXXXXX")"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT HUP INT TERM

SUMMARY_ENV="${TMP_DIR}/summary.env"
SAMPLERS_TSV="${TMP_DIR}/samplers.tsv"
FAILURES_TSV="${TMP_DIR}/failures.tsv"
SORTED_SAMPLERS_TSV="${TMP_DIR}/samplers.sorted.tsv"
SORTED_FAILURES_TSV="${TMP_DIR}/failures.sorted.tsv"
SAMPLER_ROWS_HTML="${TMP_DIR}/sampler-rows.html"
FAILURE_ROWS_HTML="${TMP_DIR}/failure-rows.html"

awk \
  -v summary_env="${SUMMARY_ENV}" \
  -v samplers_tsv="${SAMPLERS_TSV}" \
  -v failures_tsv="${FAILURES_TSV}" '
function csv_split(line, fields,    i, c, in_quotes, next_char, field, field_count) {
  delete fields
  field = ""
  field_count = 0
  in_quotes = 0

  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)

    if (in_quotes) {
      if (c == "\"") {
        next_char = substr(line, i + 1, 1)
        if (next_char == "\"") {
          field = field "\""
          i++
        } else {
          in_quotes = 0
        }
      } else {
        field = field c
      }
    } else if (c == "\"") {
      in_quotes = 1
    } else if (c == ",") {
      fields[++field_count] = field
      field = ""
    } else {
      field = field c
    }
  }

  fields[++field_count] = field
  return field_count
}
function clean_tsv(value) {
  gsub(/\t/, "    ", value)
  gsub(/\r/, " ", value)
  gsub(/\n/, " ", value)
  return value
}
BEGIN {
  OFS = "\t"
  print "label", "total", "passed", "failed", "success_rate", "avg_elapsed_ms", "avg_latency_ms", "avg_connect_ms", "max_elapsed_ms" > samplers_tsv
  print "label", "response_code", "response_message", "count" > failures_tsv
}
NR == 1 {
  next
}
{
  field_count = csv_split($0, fields)
  if (field_count < 17) {
    next
  }

  timestamp_ms = fields[1] + 0
  elapsed_ms = fields[2] + 0
  label = fields[3]
  response_code = fields[4]
  response_message = fields[5]
  success = (fields[8] == "true")
  all_threads = fields[13] + 0
  latency_ms = fields[15] + 0
  connect_ms = fields[17] + 0

  total_samples++
  successful_samples += success
  failed_samples += !success
  total_elapsed_ms += elapsed_ms
  total_latency_ms += latency_ms
  total_connect_ms += connect_ms

  if (start_timestamp_ms == 0 || timestamp_ms < start_timestamp_ms) {
    start_timestamp_ms = timestamp_ms
  }

  sample_end_timestamp_ms = timestamp_ms + elapsed_ms
  if (sample_end_timestamp_ms > end_timestamp_ms) {
    end_timestamp_ms = sample_end_timestamp_ms
  }

  if (elapsed_ms > max_elapsed_ms) {
    max_elapsed_ms = elapsed_ms
  }

  if (all_threads > peak_threads) {
    peak_threads = all_threads
  }

  per_label_total[label]++
  per_label_success[label] += success
  per_label_failed[label] += !success
  per_label_elapsed_ms[label] += elapsed_ms
  per_label_latency_ms[label] += latency_ms
  per_label_connect_ms[label] += connect_ms

  if (elapsed_ms > per_label_max_elapsed_ms[label]) {
    per_label_max_elapsed_ms[label] = elapsed_ms
  }

  if (!success) {
    failure_key = label SUBSEP response_code SUBSEP response_message
    failure_counts[failure_key]++
  }
}
END {
  if (total_samples == 0) {
    success_rate = 0
    average_elapsed_ms = 0
    average_latency_ms = 0
    average_connect_ms = 0
  } else {
    success_rate = (successful_samples * 100) / total_samples
    average_elapsed_ms = total_elapsed_ms / total_samples
    average_latency_ms = total_latency_ms / total_samples
    average_connect_ms = total_connect_ms / total_samples
  }

  print "total_samples=" total_samples > summary_env
  print "successful_samples=" successful_samples >> summary_env
  print "failed_samples=" failed_samples >> summary_env
  printf "success_rate=%.2f\n", success_rate >> summary_env
  print "start_timestamp_ms=" start_timestamp_ms >> summary_env
  print "end_timestamp_ms=" end_timestamp_ms >> summary_env
  print "duration_ms=" (end_timestamp_ms - start_timestamp_ms) >> summary_env
  printf "average_elapsed_ms=%.2f\n", average_elapsed_ms >> summary_env
  printf "average_latency_ms=%.2f\n", average_latency_ms >> summary_env
  printf "average_connect_ms=%.2f\n", average_connect_ms >> summary_env
  print "max_elapsed_ms=" max_elapsed_ms >> summary_env
  print "peak_threads=" peak_threads >> summary_env

  for (label in per_label_total) {
    printf "%s\t%d\t%d\t%d\t%.2f\t%.2f\t%.2f\t%.2f\t%d\n",
      clean_tsv(label),
      per_label_total[label],
      per_label_success[label],
      per_label_failed[label],
      (per_label_success[label] * 100) / per_label_total[label],
      per_label_elapsed_ms[label] / per_label_total[label],
      per_label_latency_ms[label] / per_label_total[label],
      per_label_connect_ms[label] / per_label_total[label],
      per_label_max_elapsed_ms[label] >> samplers_tsv
  }

  for (failure_key in failure_counts) {
    split(failure_key, parts, SUBSEP)
    printf "%s\t%s\t%s\t%d\n",
      clean_tsv(parts[1]),
      clean_tsv(parts[2]),
      clean_tsv(parts[3]),
      failure_counts[failure_key] >> failures_tsv
  }
}
' "${RESULT_FILE}"

TAB_CHAR="$(printf '\t')"
{
  sed -n '1p' "${SAMPLERS_TSV}"
  tail -n +2 "${SAMPLERS_TSV}" | sort -t "${TAB_CHAR}" -k4,4nr -k6,6nr -k2,2nr
} > "${SORTED_SAMPLERS_TSV}"

{
  sed -n '1p' "${FAILURES_TSV}"
  tail -n +2 "${FAILURES_TSV}" | sort -t "${TAB_CHAR}" -k4,4nr -k1,1
} > "${SORTED_FAILURES_TSV}"

awk -F '\t' '
function escape_html(value) {
  gsub(/&/, "\\&amp;", value)
  gsub(/</, "\\&lt;", value)
  gsub(/>/, "\\&gt;", value)
  gsub(/"/, "\\&quot;", value)
  return value
}
NR == 1 {
  next
}
{
  row_class = ($4 + 0) > 0 ? " class=\"has-failures\"" : ""
  printf "<tr%s><td>%s</td><td class=\"num\">%s</td><td class=\"num\">%s</td><td class=\"num\">%s%%</td><td class=\"num\">%s</td><td class=\"num\">%s</td></tr>\n",
    row_class,
    escape_html($1),
    $2,
    $4,
    $5,
    $6,
    $9
}' "${SORTED_SAMPLERS_TSV}" > "${SAMPLER_ROWS_HTML}"

awk -F '\t' '
function escape_html(value) {
  gsub(/&/, "\\&amp;", value)
  gsub(/</, "\\&lt;", value)
  gsub(/>/, "\\&gt;", value)
  gsub(/"/, "\\&quot;", value)
  return value
}
NR == 1 {
  next
}
{
  printf "<tr><td>%s</td><td>%s</td><td>%s</td><td class=\"num\">%s</td></tr>\n",
    escape_html($1),
    escape_html($2),
    escape_html($3),
    $4
}' "${SORTED_FAILURES_TSV}" > "${FAILURE_ROWS_HTML}"

cp "${SORTED_SAMPLERS_TSV}" "${REPORT_DIR}/sampler-breakdown.tsv"
cp "${SORTED_FAILURES_TSV}" "${REPORT_DIR}/failure-breakdown.tsv"

total_samples=0
successful_samples=0
failed_samples=0
success_rate=0
start_timestamp_ms=0
end_timestamp_ms=0
duration_ms=0
average_elapsed_ms=0
average_latency_ms=0
average_connect_ms=0
max_elapsed_ms=0
peak_threads=0

# shellcheck disable=SC1090
. "${SUMMARY_ENV}"

format_epoch_ms() {
  if [ "${1:-0}" -le 0 ]; then
    printf '%s' "n/a"
    return
  fi

  seconds=$(( $1 / 1000 ))
  if date -u -r 0 '+%Y-%m-%d %H:%M:%S UTC' >/dev/null 2>&1; then
    date -u -r "${seconds}" '+%Y-%m-%d %H:%M:%S UTC'
  else
    date -u -d "@${seconds}" '+%Y-%m-%d %H:%M:%S UTC'
  fi
}

format_duration() {
  total_seconds=$(( $1 / 1000 ))
  hours=$(( total_seconds / 3600 ))
  minutes=$(( (total_seconds % 3600) / 60 ))
  seconds=$(( total_seconds % 60 ))

  if [ "${hours}" -gt 0 ]; then
    printf '%sh %sm %ss' "${hours}" "${minutes}" "${seconds}"
  elif [ "${minutes}" -gt 0 ]; then
    printf '%sm %ss' "${minutes}" "${seconds}"
  else
    printf '%ss' "${seconds}"
  fi
}

REPORT_STARTED_AT="$(format_epoch_ms "${start_timestamp_ms}")"
REPORT_FINISHED_AT="$(format_epoch_ms "${end_timestamp_ms}")"
REPORT_DURATION="$(format_duration "${duration_ms}")"

SUCCESS_RATE_CARD_CLASS="ok"
if [ "${failed_samples}" -gt 0 ]; then
  SUCCESS_RATE_CARD_CLASS="warn"
fi

if [ -f "${REPORT_DIR}/${DASHBOARD_RELATIVE_PATH}" ]; then
  DASHBOARD_LINK_HTML="<a class=\"button\" href=\"${DASHBOARD_RELATIVE_PATH}\">Open full JMeter dashboard</a>"
  DASHBOARD_STATUS_HTML="<p class=\"hint\">The standard JMeter dashboard is still available for charts and deeper drill-down.</p>"
else
  DASHBOARD_LINK_HTML=""
  DASHBOARD_STATUS_HTML="<p class=\"hint warning\">The JMeter dashboard folder was not found, so this summary is the only generated report output for this run.</p>"
fi

if [ -s "${SAMPLER_ROWS_HTML}" ]; then
  SAMPLER_TABLE_ROWS="$(cat "${SAMPLER_ROWS_HTML}")"
else
  SAMPLER_TABLE_ROWS='<tr><td colspan="6">No sampler rows were found in the JTL.</td></tr>'
fi

if [ -s "${FAILURE_ROWS_HTML}" ]; then
  FAILURE_TABLE_ROWS="$(cat "${FAILURE_ROWS_HTML}")"
else
  FAILURE_TABLE_ROWS='<tr><td colspan="4">No failed samples were recorded.</td></tr>'
fi

cat > "${REPORT_DIR}/summary.txt" <<EOF
Run label: ${RUN_LABEL}
Result file: $(basename "${RESULT_FILE}")
Samples: ${total_samples}
Successful samples: ${successful_samples}
Failed samples: ${failed_samples}
Success rate: ${success_rate}%
Started at: ${REPORT_STARTED_AT}
Finished at: ${REPORT_FINISHED_AT}
Duration: ${REPORT_DURATION}
Average elapsed: ${average_elapsed_ms} ms
Average latency: ${average_latency_ms} ms
Average connect time: ${average_connect_ms} ms
Max elapsed: ${max_elapsed_ms} ms
Peak concurrent threads: ${peak_threads}
Dashboard path: ${DASHBOARD_RELATIVE_PATH}
EOF

cat > "${REPORT_DIR}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>APHA Integration Bridge Perf Test Report</title>
  <style>
    :root {
      --bg: #f3efe7;
      --ink: #1f2a2e;
      --muted: #5f6f72;
      --card: rgba(255, 255, 255, 0.86);
      --line: rgba(31, 42, 46, 0.12);
      --accent: #2a7f62;
      --accent-soft: rgba(42, 127, 98, 0.14);
      --warn: #a44d23;
      --warn-soft: rgba(164, 77, 35, 0.14);
      --shadow: 0 18px 40px rgba(31, 42, 46, 0.08);
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, rgba(42, 127, 98, 0.18), transparent 32%),
        linear-gradient(180deg, #f7f2e9 0%, var(--bg) 55%, #ede7db 100%);
      line-height: 1.5;
    }

    .page {
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
      padding: 36px 0 56px;
    }

    .hero,
    .panel {
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 22px;
      box-shadow: var(--shadow);
      backdrop-filter: blur(10px);
    }

    .hero {
      padding: 32px;
      margin-bottom: 24px;
    }

    .eyebrow {
      margin: 0 0 10px;
      color: var(--accent);
      font-size: 0.86rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }

    h1, h2 {
      margin: 0;
      font-weight: 600;
      letter-spacing: -0.02em;
    }

    h1 {
      font-size: clamp(2rem, 4vw, 3.2rem);
      margin-bottom: 10px;
    }

    h2 {
      font-size: 1.35rem;
      margin-bottom: 18px;
    }

    p {
      margin: 0;
    }

    .hero-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 18px;
      color: var(--muted);
      font-size: 0.96rem;
    }

    .hero-actions {
      margin-top: 22px;
    }

    .button {
      display: inline-block;
      padding: 12px 18px;
      border-radius: 999px;
      background: var(--accent);
      color: #fff;
      text-decoration: none;
      font-weight: 600;
    }

    .hint {
      margin-top: 14px;
      color: var(--muted);
      font-size: 0.95rem;
    }

    .warning {
      color: var(--warn);
    }

    .metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }

    .metric {
      padding: 20px;
    }

    .metric .label {
      display: block;
      color: var(--muted);
      font-size: 0.86rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      margin-bottom: 8px;
    }

    .metric .value {
      display: block;
      font-size: 1.8rem;
      font-weight: 600;
      letter-spacing: -0.03em;
    }

    .metric.warn {
      background: linear-gradient(180deg, #fff 0%, var(--warn-soft) 100%);
    }

    .metric.ok {
      background: linear-gradient(180deg, #fff 0%, var(--accent-soft) 100%);
    }

    .layout {
      display: grid;
      grid-template-columns: 1.3fr 0.9fr;
      gap: 24px;
    }

    .panel {
      padding: 24px;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.96rem;
    }

    th,
    td {
      padding: 12px 10px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
      text-align: left;
    }

    th {
      color: var(--muted);
      font-size: 0.82rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    td.num {
      text-align: right;
      white-space: nowrap;
      font-variant-numeric: tabular-nums;
    }

    tr.has-failures td:first-child {
      color: var(--warn);
      font-weight: 600;
    }

    .footnote {
      margin-top: 18px;
      color: var(--muted);
      font-size: 0.9rem;
    }

    @media (max-width: 900px) {
      .layout {
        grid-template-columns: 1fr;
      }

      .page {
        width: min(100% - 20px, 1120px);
        padding-top: 20px;
      }

      .hero,
      .panel,
      .metric {
        border-radius: 18px;
      }
    }
  </style>
</head>
<body>
  <main class="page">
    <section class="hero">
      <p class="eyebrow">APHA Integration Bridge Boundary Test</p>
      <h1>Run ${RUN_LABEL}</h1>
      <p>This summary pulls the most important pass, failure, and latency numbers to the front so the report is easier to scan before diving into the full dashboard.</p>
      <div class="hero-meta">
        <span>Started ${REPORT_STARTED_AT}</span>
        <span>Finished ${REPORT_FINISHED_AT}</span>
        <span>Duration ${REPORT_DURATION}</span>
      </div>
      <div class="hero-actions">
        ${DASHBOARD_LINK_HTML}
        ${DASHBOARD_STATUS_HTML}
      </div>
    </section>

    <section class="metrics">
      <article class="panel metric ok">
        <span class="label">Samples</span>
        <span class="value">${total_samples}</span>
      </article>
      <article class="panel metric ${SUCCESS_RATE_CARD_CLASS}">
        <span class="label">Success Rate</span>
        <span class="value">${success_rate}%</span>
      </article>
      <article class="panel metric warn">
        <span class="label">Failed Samples</span>
        <span class="value">${failed_samples}</span>
      </article>
      <article class="panel metric">
        <span class="label">Average Elapsed</span>
        <span class="value">${average_elapsed_ms} ms</span>
      </article>
      <article class="panel metric">
        <span class="label">Max Elapsed</span>
        <span class="value">${max_elapsed_ms} ms</span>
      </article>
      <article class="panel metric">
        <span class="label">Peak Threads</span>
        <span class="value">${peak_threads}</span>
      </article>
    </section>

    <section class="layout">
      <section class="panel">
        <h2>Sampler Breakdown</h2>
        <table>
          <thead>
            <tr>
              <th>Sampler</th>
              <th class="num">Samples</th>
              <th class="num">Failed</th>
              <th class="num">Success</th>
              <th class="num">Avg ms</th>
              <th class="num">Max ms</th>
            </tr>
          </thead>
          <tbody>
            ${SAMPLER_TABLE_ROWS}
          </tbody>
        </table>
        <p class="footnote">The full sorted breakdown is also saved as <code>sampler-breakdown.tsv</code> in this report folder.</p>
      </section>

      <section class="panel">
        <h2>Failure Breakdown</h2>
        <table>
          <thead>
            <tr>
              <th>Sampler</th>
              <th>Code</th>
              <th>Message</th>
              <th class="num">Count</th>
            </tr>
          </thead>
          <tbody>
            ${FAILURE_TABLE_ROWS}
          </tbody>
        </table>
        <p class="footnote">A tab-separated copy is also saved as <code>failure-breakdown.tsv</code> for spreadsheet or pipeline use.</p>
      </section>
    </section>
  </main>
</body>
</html>
EOF
