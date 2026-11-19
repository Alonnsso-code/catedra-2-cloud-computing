#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

EVIDENCE_DIR="docs/evidence"
mkdir -p "$EVIDENCE_DIR"
LOG_FILE="$EVIDENCE_DIR/validation-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee "$LOG_FILE") 2>&1

section() {
  printf '\n===== %s =====\n' "$1"
}

wait_for_api() {
  local attempt
  for attempt in $(seq 1 30); do
    if curl -fsS http://localhost:8080/api/health > /tmp/c2-health.json; then
      cat /tmp/c2-health.json
      return 0
    fi
    sleep 2
  done
  echo "ERROR: API did not become healthy within 60 seconds."
  docker compose ps -a
  docker compose logs --tail=80 db backend frontend
  return 1
}

section "Docker toolchain"
docker --version
docker compose version

section "Compose configuration"
docker compose config -q
echo "PASS: docker compose config -q"

section "Clean stop before startup"
docker compose down

section "Required clean startup"
docker compose up --build -d
docker compose ps
wait_for_api
echo "PASS: API and PostgreSQL health endpoint"

section "Frontend to backend to PostgreSQL communication"
ITEM="codespace-validation-$(date -u +%Y%m%dT%H%M%SZ)"
echo "Test item: $ITEM"
POST_RESPONSE="$(curl -fsS -X POST http://localhost:8080/api/items \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$ITEM\"}")"
printf '%s\n' "$POST_RESPONSE"
ITEMS_BEFORE_RECREATE="$(curl -fsS http://localhost:8080/api/items)"
printf '%s\n' "$ITEMS_BEFORE_RECREATE"
grep -Fq "$ITEM" <<< "$POST_RESPONSE"
grep -Fq "$ITEM" <<< "$ITEMS_BEFORE_RECREATE"
echo "PASS: item created and returned through Nginx"

section "Persistence after container recreation"
docker compose down
docker compose up --build -d
docker compose ps
wait_for_api
ITEMS_AFTER_RECREATE="$(curl -fsS http://localhost:8080/api/items)"
printf '%s\n' "$ITEMS_AFTER_RECREATE"
grep -Fq "$ITEM" <<< "$ITEMS_AFTER_RECREATE"
docker volume ls --filter name=postgres_data
echo "PASS: item survived docker compose down and container recreation"

section "Controlled backend failure"
docker compose stop backend
docker compose ps -a
set +e
FAILURE_HTTP_CODE="$(curl -sS -o /tmp/c2-health-failure.txt -w '%{http_code}' \
  http://localhost:8080/api/health)"
CURL_STATUS=$?
set -e
printf 'curl exit status: %s; HTTP status: %s\n' "$CURL_STATUS" "$FAILURE_HTTP_CODE"
cat /tmp/c2-health-failure.txt || true
docker compose logs --tail=40 backend frontend
if [[ "$FAILURE_HTTP_CODE" == "502" || "$FAILURE_HTTP_CODE" == "503" || "$FAILURE_HTTP_CODE" == "504" ]]; then
  echo "PASS: API became unavailable while backend was stopped"
else
  echo "ERROR: Expected an unavailable-service HTTP status (502/503/504)."
  exit 1
fi

section "Backend recovery"
docker compose start backend
wait_for_api
docker compose ps
echo "PASS: API recovered after backend restart"

section "Evidence file"
echo "$LOG_FILE"
