#!/usr/bin/env bash
set -euo pipefail

readonly KIBANA_URL="http://kibana:5601"
readonly DASHBOARDS_FILE="/setup/dashboards.ndjson"

result="$(curl -fsS -u "elastic:${ELASTIC_PASSWORD}" -H "kbn-xsrf: true" \
  -X POST "${KIBANA_URL}/api/saved_objects/_import?overwrite=true" --form "file=@${DASHBOARDS_FILE}")"

if [[ "$result" != *'"success":true'* ]]; then
  echo "Kibana rejected the dashboards: $result" >&2
  exit 1
fi
echo "The Kibana dashboards are in place."
