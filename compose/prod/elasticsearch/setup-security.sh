#!/usr/bin/env bash
set -euo pipefail

readonly ELASTICSEARCH_URL="http://elasticsearch:9200"

call() {
  curl -fsS -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json" "$@" >/dev/null
}

call -X POST "${ELASTICSEARCH_URL}/_security/user/kibana_system/_password" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}"

call -X PUT "${ELASTICSEARCH_URL}/_security/role/wortlaut_reader" \
  -d '{"cluster":["monitor"],"indices":[{"names":["speeches*"],"privileges":["read"]}]}'
call -X PUT "${ELASTICSEARCH_URL}/_security/user/${API_ES_USERNAME}" \
  -d "{\"password\":\"${API_ES_PASSWORD}\",\"roles\":[\"wortlaut_reader\"]}"

call -X PUT "${ELASTICSEARCH_URL}/_security/role/wortlaut_writer" \
  -d '{"cluster":["monitor","manage_index_templates"],"indices":[{"names":["speeches*"],"privileges":["all"]}]}'
call -X PUT "${ELASTICSEARCH_URL}/_security/user/${INDEXER_ES_USERNAME}" \
  -d "{\"password\":\"${INDEXER_ES_PASSWORD}\",\"roles\":[\"wortlaut_writer\"]}"

echo "Elasticsearch users and roles are in place."
