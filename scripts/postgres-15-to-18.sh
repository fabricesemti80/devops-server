#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-}"
BACKUP_DIR="${POSTGRES_MIGRATION_BACKUP_DIR:-./backups/postgres-15}"
WIKI_TEMP_CONTAINER="devops-migrate-wikijs-pg15"
SEMAPHORE_TEMP_CONTAINER="devops-migrate-semaphore-pg15"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

required_vars=(
  WIKI_DB_USER WIKI_DB_PASS WIKI_DB_NAME
  SEMAPHORE_DB_USER SEMAPHORE_DB_PASS SEMAPHORE_DB_NAME
)

for variable in "${required_vars[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required variable ${variable} is unset. Check .env." >&2
    exit 1
  fi
done

project_name="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
WIKI_PG15_VOLUME="${WIKI_PG15_VOLUME:-${project_name}_wikijs_db_data}"
SEMAPHORE_PG15_VOLUME="${SEMAPHORE_PG15_VOLUME:-${project_name}_semaphore_db_data}"

cleanup() {
  docker rm -f "$WIKI_TEMP_CONTAINER" "$SEMAPHORE_TEMP_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_ready() {
  local container="$1"
  local user="$2"
  local database="$3"

  for _ in {1..60}; do
    if docker exec "$container" pg_isready -U "$user" -d "$database" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "PostgreSQL in ${container} did not become ready." >&2
  docker logs "$container" >&2 || true
  return 1
}

start_pg15() {
  local container="$1"
  local volume="$2"
  local password="$3"

  docker volume inspect "$volume" >/dev/null
  docker run --detach --rm \
    --name "$container" \
    --env POSTGRES_PASSWORD="$password" \
    --volume "$volume:/var/lib/postgresql/data" \
    postgres:15-alpine >/dev/null
}

backup() {
  mkdir -p "$BACKUP_DIR"

  if [[ -e "$BACKUP_DIR/wikijs.dump" || -e "$BACKUP_DIR/semaphore.dump" ]]; then
    echo "Backup files already exist in ${BACKUP_DIR}; move them aside before retrying." >&2
    exit 1
  fi

  echo "Checking retained PostgreSQL 15 volumes..."
  docker volume inspect "$WIKI_PG15_VOLUME" "$SEMAPHORE_PG15_VOLUME" >/dev/null

  echo "Stopping the application stack without deleting volumes..."
  docker compose down

  echo "Exporting Wiki.js from ${WIKI_PG15_VOLUME}..."
  start_pg15 "$WIKI_TEMP_CONTAINER" "$WIKI_PG15_VOLUME" "$WIKI_DB_PASS"
  wait_ready "$WIKI_TEMP_CONTAINER" "$WIKI_DB_USER" "$WIKI_DB_NAME"
  docker exec "$WIKI_TEMP_CONTAINER" \
    pg_dump -U "$WIKI_DB_USER" -d "$WIKI_DB_NAME" --format=custom \
    > "$BACKUP_DIR/wikijs.dump"
  docker rm -f "$WIKI_TEMP_CONTAINER" >/dev/null

  echo "Exporting Semaphore from ${SEMAPHORE_PG15_VOLUME}..."
  start_pg15 "$SEMAPHORE_TEMP_CONTAINER" "$SEMAPHORE_PG15_VOLUME" "$SEMAPHORE_DB_PASS"
  wait_ready "$SEMAPHORE_TEMP_CONTAINER" "$SEMAPHORE_DB_USER" "$SEMAPHORE_DB_NAME"
  docker exec "$SEMAPHORE_TEMP_CONTAINER" \
    pg_dump -U "$SEMAPHORE_DB_USER" -d "$SEMAPHORE_DB_NAME" --format=custom \
    > "$BACKUP_DIR/semaphore.dump"
  docker rm -f "$SEMAPHORE_TEMP_CONTAINER" >/dev/null

  {
    echo "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "source_postgres_major=15"
    echo "wiki_source_volume=$WIKI_PG15_VOLUME"
    echo "semaphore_source_volume=$SEMAPHORE_PG15_VOLUME"
    sha256sum "$BACKUP_DIR/wikijs.dump" "$BACKUP_DIR/semaphore.dump"
  } > "$BACKUP_DIR/manifest.txt"

  echo "Backups created in ${BACKUP_DIR}."
  echo "Review manifest.txt, then run: task postgres:restore:18"
}

restore() {
  [[ -s "$BACKUP_DIR/wikijs.dump" ]] || {
    echo "Missing Wiki.js backup: ${BACKUP_DIR}/wikijs.dump" >&2
    exit 1
  }
  [[ -s "$BACKUP_DIR/semaphore.dump" ]] || {
    echo "Missing Semaphore backup: ${BACKUP_DIR}/semaphore.dump" >&2
    exit 1
  }

  echo "Starting clean PostgreSQL 18 services..."
  docker compose up -d wikijs-db semaphore-db
  wait_ready "wikijs-db" "$WIKI_DB_USER" "$WIKI_DB_NAME"
  wait_ready "semaphore-db" "$SEMAPHORE_DB_USER" "$SEMAPHORE_DB_NAME"

  echo "Restoring Wiki.js..."
  docker exec -i wikijs-db pg_restore \
    -U "$WIKI_DB_USER" -d "$WIKI_DB_NAME" \
    --clean --if-exists --no-owner --exit-on-error \
    < "$BACKUP_DIR/wikijs.dump"

  echo "Restoring Semaphore..."
  docker exec -i semaphore-db pg_restore \
    -U "$SEMAPHORE_DB_USER" -d "$SEMAPHORE_DB_NAME" \
    --clean --if-exists --no-owner --exit-on-error \
    < "$BACKUP_DIR/semaphore.dump"

  verify
  echo "Restore complete. Start the application with task up or task up:ca-trust."
}

verify_database() {
  local container="$1"
  local user="$2"
  local database="$3"
  local version
  local table_count

  version="$(docker exec "$container" psql -U "$user" -d "$database" -Atc "SHOW server_version;")"
  table_count="$(docker exec "$container" psql -U "$user" -d "$database" -Atc \
    "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');")"

  if [[ "$version" != 18.* ]]; then
    echo "${container}: expected PostgreSQL 18, found ${version}" >&2
    return 1
  fi

  echo "${container}: PostgreSQL ${version}, user tables=${table_count}"
}

verify() {
  wait_ready "wikijs-db" "$WIKI_DB_USER" "$WIKI_DB_NAME"
  wait_ready "semaphore-db" "$SEMAPHORE_DB_USER" "$SEMAPHORE_DB_NAME"
  verify_database "wikijs-db" "$WIKI_DB_USER" "$WIKI_DB_NAME"
  verify_database "semaphore-db" "$SEMAPHORE_DB_USER" "$SEMAPHORE_DB_NAME"
}

case "$ACTION" in
  backup)
    backup
    ;;
  restore)
    restore
    ;;
  verify)
    verify
    ;;
  *)
    echo "Usage: $0 {backup|restore|verify}" >&2
    exit 2
    ;;
esac
