#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

CURRENT_PHASE="startup"
WORKSPACE=""
WORKSPACE_ROOT=""
PROJECT_NAME=""
COMPOSE_FILE=""
COMPOSE_DIAGNOSTICS_READY=0

DOCKER_INFO_TIMEOUT_SECONDS=60
DOCKER_CONTROL_TIMEOUT_SECONDS=30
DOCKER_PULL_TIMEOUT_SECONDS=600
COMPOSE_BUILD_TIMEOUT_SECONDS=900
COMPOSE_WAIT_TIMEOUT_SECONDS=300
COMPOSE_UP_TIMEOUT_SECONDS=360
COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS=30
COMPOSE_DOWN_TIMEOUT_SECONDS=120
COMPOSE_LOG_TAIL_LINES=200
readonly DOCKER_INFO_TIMEOUT_SECONDS DOCKER_CONTROL_TIMEOUT_SECONDS
readonly DOCKER_PULL_TIMEOUT_SECONDS COMPOSE_BUILD_TIMEOUT_SECONDS
readonly COMPOSE_WAIT_TIMEOUT_SECONDS COMPOSE_UP_TIMEOUT_SECONDS
readonly COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS COMPOSE_DOWN_TIMEOUT_SECONDS
readonly COMPOSE_LOG_TAIL_LINES

phase() {
  CURRENT_PHASE="$1"
  printf '[acceptance] phase=%s\n' "${CURRENT_PHASE}"
}

phase "startup"

die() {
  printf 'Production acceptance failed during phase %s: %s\n' \
    "${CURRENT_PHASE}" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

run_with_timeout() {
  local seconds="$1"
  shift

  timeout -k 10 "${seconds}" "$@"
}

compose_with_timeout() {
  local seconds="$1"
  shift

  run_with_timeout "${seconds}" \
    docker compose --project-name "${PROJECT_NAME}" --file "${COMPOSE_FILE}" "$@"
}

collect_compose_diagnostics() {
  [[ "${COMPOSE_DIAGNOSTICS_READY}" == "1" ]] || return 0

  printf '[acceptance] diagnostics=compose-ps phase=%s\n' "${CURRENT_PHASE}" >&2
  compose_with_timeout "${COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS}" \
    ps --all >&2 || printf '[acceptance] diagnostics=compose-ps-unavailable\n' >&2
  printf '[acceptance] diagnostics=compose-logs phase=%s tail=%s\n' \
    "${CURRENT_PHASE}" "${COMPOSE_LOG_TAIL_LINES}" >&2
  compose_with_timeout "${COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS}" \
    logs --no-color --tail "${COMPOSE_LOG_TAIL_LINES}" >&2 || \
    printf '[acceptance] diagnostics=compose-logs-unavailable\n' >&2
}

cleanup() {
  local status=$?
  local exit_phase="${CURRENT_PHASE}"

  trap - EXIT INT TERM
  printf '[acceptance] exit phase=%s status=%s\n' "${exit_phase}" "${status}" >&2

  if ((status != 0)); then
    collect_compose_diagnostics
  fi

  if [[ "${PROJECT_NAME}" =~ ^mcwebacceptance[0-9]+_[0-9]+$ ]]; then
    printf '[acceptance] phase=compose-down timeout_seconds=%s\n' \
      "${COMPOSE_DOWN_TIMEOUT_SECONDS}" >&2
    if compose_with_timeout "${COMPOSE_DOWN_TIMEOUT_SECONDS}" \
      down --volumes --remove-orphans >/dev/null 2>&1; then
      printf '[acceptance] compose-down=complete\n' >&2
    else
      printf '[acceptance] compose-down=failed-or-timed-out\n' >&2
      status=1
    fi
  fi

  if [[ -n "${WORKSPACE}" && -d "${WORKSPACE}" && -n "${WORKSPACE_ROOT}" ]]; then
    case "${WORKSPACE}" in
      "${WORKSPACE_ROOT%/}"/mcweb-acceptance.*)
        rm -rf -- "${WORKSPACE}"
        ;;
    esac
  fi

  printf '[acceptance] exit-complete phase=%s status=%s\n' \
    "${exit_phase}" "${status}" >&2
  exit "${status}"
}

for command in docker openssl bundle ruby psql createdb pg_dump pg_restore realpath mktemp grep timeout; do
  require_command "${command}"
done
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

phase "docker-daemon-check"
if ! run_with_timeout "${DOCKER_INFO_TIMEOUT_SECONDS}" docker info >/dev/null 2>&1; then
  die "Docker daemon did not answer the bounded readiness check"
fi
if ! run_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
  docker compose version >/dev/null 2>&1
then
  die "Docker Compose did not answer the bounded version check"
fi
pg_dump --version | grep -Eq ' 18\.' ||
  die "PostgreSQL 18 client tools are required for the PostgreSQL 18 acceptance service"

phase "workspace-preparation"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${APP_ROOT}/deploy/acceptance/docker-compose.yml"
WORKSPACE_ROOT_INPUT="${CNB_BUILD_WORKSPACE:-${TMPDIR:-/tmp}}"
WORKSPACE_ROOT="$(realpath --canonicalize-existing "${WORKSPACE_ROOT_INPUT}")"
WORKSPACE="$(mktemp -d "${WORKSPACE_ROOT%/}/mcweb-acceptance.XXXXXX")"
PROJECT_NAME="mcwebacceptance$$_${RANDOM}"
CERTS_DIR="${WORKSPACE}/certs"
DOCKER_ENDPOINT="${DOCKER_HOST:-}"
if [[ -z "${DOCKER_ENDPOINT}" ]]; then
  DOCKER_ENDPOINT="$(
    run_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
      docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true
  )"
fi

valid_ipv4() {
  local value="$1"
  local octet
  local -a octets

  [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  [[ "${value}" != "0.0.0.0" ]] || return 1
  IFS=. read -r -a octets <<<"${value}"
  for octet in "${octets[@]}"; do
    ((10#${octet} <= 255)) || return 1
  done
}

CNB_ACCEPTANCE_SERVICE_HOST=""
if [[ -n "${CNB_RUNNER_IP:-}" ]]; then
  valid_ipv4 "${CNB_RUNNER_IP}" || die "CNB_RUNNER_IP is not a usable IPv4 address"
  CNB_ACCEPTANCE_SERVICE_HOST="${CNB_RUNNER_IP}"
fi

acceptance_service_host() {
  local authority

  if [[ -n "${CNB_ACCEPTANCE_SERVICE_HOST}" ]]; then
    printf '%s\n' "${CNB_ACCEPTANCE_SERVICE_HOST}"
    return 0
  fi

  case "${DOCKER_ENDPOINT}" in
    ""|unix://*)
      printf '%s\n' "127.0.0.1"
      ;;
    tcp://*)
      authority="${DOCKER_ENDPOINT#tcp://}"
      authority="${authority%%/*}"
      if [[ "${authority}" =~ ^([A-Za-z0-9._-]+):[0-9]+$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      else
        die "could not resolve the Docker service host from DOCKER_HOST"
      fi
      ;;
    *)
      die "production acceptance requires a local or TCP Docker endpoint"
      ;;
  esac
}

ACCEPTANCE_SERVICE_HOST="$(acceptance_service_host)"
if [[ -z "${MCWEB_ACCEPTANCE_PUBLISH_HOST:-}" ]]; then
  if [[ -n "${CNB_ACCEPTANCE_SERVICE_HOST}" || "${DOCKER_ENDPOINT}" == tcp://* ]]; then
    MCWEB_ACCEPTANCE_PUBLISH_HOST="0.0.0.0"
  else
    MCWEB_ACCEPTANCE_PUBLISH_HOST="127.0.0.1"
  fi
fi
case "${MCWEB_ACCEPTANCE_PUBLISH_HOST}" in
  127.0.0.1|0.0.0.0)
    ;;
  *)
    die "MCWEB_ACCEPTANCE_PUBLISH_HOST must be 127.0.0.1 or 0.0.0.0"
    ;;
esac
export MCWEB_ACCEPTANCE_PUBLISH_HOST
export NO_PROXY="${NO_PROXY:+${NO_PROXY},}${ACCEPTANCE_SERVICE_HOST}"
export no_proxy="${no_proxy:+${no_proxy},}${ACCEPTANCE_SERVICE_HOST}"

if [[ "${ACCEPTANCE_SERVICE_HOST}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  ACCEPTANCE_SERVICE_SAN="IP:${ACCEPTANCE_SERVICE_HOST}"
elif [[ "${ACCEPTANCE_SERVICE_HOST}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  ACCEPTANCE_SERVICE_SAN="DNS:${ACCEPTANCE_SERVICE_HOST}"
else
  die "Docker service host cannot be represented in the acceptance certificate"
fi

case "${WORKSPACE}" in
  "${WORKSPACE_ROOT%/}"/mcweb-acceptance.*)
    ;;
  *)
    die "temporary workspace is outside the accepted prefix: ${WORKSPACE}"
    ;;
esac
[[ "${PROJECT_NAME}" =~ ^mcwebacceptance[0-9]+_[0-9]+$ ]] ||
  die "unsafe Docker Compose project name"

pull_dependency_image() {
  local dependency="$1"
  local image="$2"
  local inspect_status

  phase "dependency-image-${dependency}"
  if run_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
    docker image inspect "${image}" >/dev/null 2>&1
  then
    printf '[acceptance] dependency-image=%s action=reuse-exact\n' "${dependency}"
    return 0
  else
    inspect_status=$?
  fi
  if [[ "${inspect_status}" == "124" || "${inspect_status}" == "137" ]]; then
    die "${dependency} dependency image inspection timed out"
  fi

  printf '[acceptance] dependency-image=%s action=pull-start timeout_seconds=%s\n' \
    "${dependency}" "${DOCKER_PULL_TIMEOUT_SECONDS}"
  if ! run_with_timeout "${DOCKER_PULL_TIMEOUT_SECONDS}" docker pull "${image}"; then
    die "${dependency} dependency image pull failed or timed out"
  fi
  printf '[acceptance] dependency-image=%s action=pull-complete\n' "${dependency}"
}

prepare_dependency_images() {
  local cached_inputs="${MCWEB_ACCEPTANCE_REQUIRE_CACHED_INPUTS:-0}"

  if [[ "${cached_inputs}" != "1" ]]; then
    pull_dependency_image \
      "postgres" "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-postgres:18.4-trixie}"
    pull_dependency_image \
      "redis" "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-redis:8.8.1-alpine3.23}"
    phase "dependency-image-minio-build"
    if ! compose_with_timeout "${COMPOSE_BUILD_TIMEOUT_SECONDS}" build minio; then
      die "local MinIO dependency image build failed or timed out"
    fi
    printf '[acceptance] dependency-image=minio action=build-complete\n'
    return 0
  fi

  [[ -n "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-}" ]] ||
    die "MCWEB_ACCEPTANCE_POSTGRES_IMAGE is required when cached inputs are enforced"
  [[ -n "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-}" ]] ||
    die "MCWEB_ACCEPTANCE_REDIS_IMAGE is required when cached inputs are enforced"
  [[ -n "${MCWEB_ACCEPTANCE_MINIO_IMAGE:-}" ]] ||
    die "MCWEB_ACCEPTANCE_MINIO_IMAGE is required when cached inputs are enforced"

  pull_dependency_image "postgres" "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE}"
  pull_dependency_image "redis" "${MCWEB_ACCEPTANCE_REDIS_IMAGE}"
  pull_dependency_image "minio" "${MCWEB_ACCEPTANCE_MINIO_IMAGE}"
}

phase "ephemeral-tls"
mkdir -p "${CERTS_DIR}/CAs"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -days 2 \
  -subj "/CN=McWeb acceptance CA" \
  -keyout "${WORKSPACE}/ca.key" \
  -out "${WORKSPACE}/ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -sha256 -nodes \
  -subj "/CN=minio" \
  -keyout "${CERTS_DIR}/private.key" \
  -out "${WORKSPACE}/minio.csr" >/dev/null 2>&1
cat > "${WORKSPACE}/minio.ext" <<EOF
subjectAltName=DNS:minio,DNS:localhost,IP:127.0.0.1,${ACCEPTANCE_SERVICE_SAN}
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -sha256 -days 2 \
  -in "${WORKSPACE}/minio.csr" \
  -CA "${WORKSPACE}/ca.crt" \
  -CAkey "${WORKSPACE}/ca.key" \
  -CAcreateserial \
  -extfile "${WORKSPACE}/minio.ext" \
  -out "${CERTS_DIR}/public.crt" >/dev/null 2>&1
cp "${WORKSPACE}/ca.crt" "${CERTS_DIR}/CAs/acceptance-ca.crt"
# The key only protects an ephemeral loopback test service; make it readable by
# the unprivileged container uid and destroy it with the unique workspace.
chmod 0755 "${CERTS_DIR}" "${CERTS_DIR}/CAs"
chmod 0644 "${CERTS_DIR}/private.key" "${CERTS_DIR}/public.crt" "${CERTS_DIR}/CAs/acceptance-ca.crt"

export MCWEB_ACCEPTANCE_CERTS_DIR
MCWEB_ACCEPTANCE_CERTS_DIR="$(realpath --canonicalize-existing "${CERTS_DIR}")"
export MCWEB_ACCEPTANCE_POSTGRES_PASSWORD="acceptance-postgres-password"
export MCWEB_ACCEPTANCE_S3_ACCESS_KEY="mcweb_acceptance_access"
export MCWEB_ACCEPTANCE_S3_SECRET_KEY="mcweb-acceptance-secret-key-000000000000"

cd "${APP_ROOT}"
if [[ "${MCWEB_ACCEPTANCE_SKIP_APP_IMAGE_BUILD:-0}" != "1" ]]; then
  phase "application-image-build"
  docker build \
    --file deploy/docker/Dockerfile \
    --tag "${PROJECT_NAME}-app:acceptance" \
    .
fi
prepare_dependency_images
phase "compose-up"
COMPOSE_DIAGNOSTICS_READY=1
if ! compose_with_timeout "${COMPOSE_UP_TIMEOUT_SECONDS}" \
  up --detach --no-build --pull never --wait \
  --wait-timeout "${COMPOSE_WAIT_TIMEOUT_SECONDS}"
then
  die "Docker Compose dependencies did not become healthy before the bounded wait"
fi
printf '[acceptance] compose-up=complete\n'

published_port() {
  local service="$1"
  local container_port="$2"
  local address port
  address="$(
    compose_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
      port "${service}" "${container_port}"
  )"
  port="${address##*:}"
  [[ "${port}" =~ ^[0-9]+$ ]] || die "could not resolve ${service} port from ${address}"
  printf '%s\n' "${port}"
}

phase "published-port-discovery"
export PGHOST="${ACCEPTANCE_SERVICE_HOST}"
export PGPORT
PGPORT="$(published_port postgres 5432)"
export PGUSER=postgres
export PGPASSWORD="${MCWEB_ACCEPTANCE_POSTGRES_PASSWORD}"
REDIS_PORT="$(published_port redis 6379)"
MINIO_PORT="$(published_port minio 9000)"

phase "postgres-readiness"
postgres_ready=0
for attempt in $(seq 1 60); do
  if psql --dbname=postgres --no-psqlrc --set=ON_ERROR_STOP=1 \
    --command="SELECT 1" >/dev/null 2>&1; then
    postgres_ready=1
    break
  fi

  sleep 1
done

if [[ "${postgres_ready}" != "1" ]]; then
  compose ps postgres >&2 || true
  die "PostgreSQL published port did not become reachable"
fi

export RAILS_ENV=production
export MCWEB_DEVELOPER_MODE="0"
export SECRET_KEY_BASE="acceptance-secret-key-base-000000000000000000000000000000000000000000000000000000000000"
export LOCKBOX_MASTER_KEY="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export RAILS_INBOUND_EMAIL_PASSWORD="acceptance-inbound-email-password-000000000000000000000000"
export MCWEB_PUBLIC_URL="https://acceptance.mcweb.internal"
export MCWEB_ALLOWED_HOSTS="acceptance.mcweb.internal"
export MCWEB_TRUSTED_PROXIES="127.0.0.1/32"
export MCWEB_SMTP_ADDRESS="127.0.0.1"
export MCWEB_SMTP_PORT="2525"
export MCWEB_SMTP_AUTHENTICATION="none"
export MCWEB_SMTP_TLS="starttls"
export MCWEB_SMTP_USERNAME=""
export MCWEB_SMTP_PASSWORD=""
export MCWEB_MAIL_FROM="acceptance@mcweb.internal"
export MCWEB_ACTIVE_STORAGE_SERVICE="private_s3"
export MCWEB_S3_BUCKET="mcweb-acceptance"
export MCWEB_S3_REGION="us-east-1"
export MCWEB_S3_ACCESS_KEY_ID="${MCWEB_ACCEPTANCE_S3_ACCESS_KEY}"
export MCWEB_S3_SECRET_ACCESS_KEY="${MCWEB_ACCEPTANCE_S3_SECRET_KEY}"
export MCWEB_S3_ENDPOINT="https://${ACCEPTANCE_SERVICE_HOST}:${MINIO_PORT}"
export MCWEB_S3_FORCE_PATH_STYLE="1"
export MCWEB_BACKUP_S3_BUCKET="mcweb-acceptance-backups"
export MCWEB_BACKUP_S3_REGION="us-east-1"
export MCWEB_BACKUP_S3_ACCESS_KEY_ID="${MCWEB_ACCEPTANCE_S3_ACCESS_KEY}"
export MCWEB_BACKUP_S3_SECRET_ACCESS_KEY="${MCWEB_ACCEPTANCE_S3_SECRET_KEY}"
export MCWEB_BACKUP_S3_ENDPOINT="https://${ACCEPTANCE_SERVICE_HOST}:${MINIO_PORT}"
export MCWEB_BACKUP_S3_FORCE_PATH_STYLE="1"
export MCWEB_BACKUP_S3_PREFIX="acceptance-backups"
export MCWEB_RESTORE_S3_BUCKET="mcweb-acceptance-restore"
export MCWEB_RESTORE_S3_REGION="us-east-1"
export MCWEB_RESTORE_S3_ACCESS_KEY_ID="${MCWEB_ACCEPTANCE_S3_ACCESS_KEY}"
export MCWEB_RESTORE_S3_SECRET_ACCESS_KEY="${MCWEB_ACCEPTANCE_S3_SECRET_KEY}"
export MCWEB_RESTORE_S3_ENDPOINT="https://${ACCEPTANCE_SERVICE_HOST}:${MINIO_PORT}"
export MCWEB_RESTORE_S3_FORCE_PATH_STYLE="1"
export SSL_CERT_FILE="${WORKSPACE}/ca.crt"
export AWS_CA_BUNDLE="${WORKSPACE}/ca.crt"
export AWS_EC2_METADATA_DISABLED="true"
export AWS_MAX_ATTEMPTS="1"
export REDIS_URL="redis://${ACCEPTANCE_SERVICE_HOST}:${REDIS_PORT}/0"
export MCWEB_DATABASE_HOST="${PGHOST}"
export MCWEB_DATABASE_PORT="${PGPORT}"
export MCWEB_DATABASE_USERNAME="${PGUSER}"
export MCWEB_DATABASE_PASSWORD="${PGPASSWORD}"
export MCWEB_CONFIG_FILE="${WORKSPACE}/intentionally-absent.env"
export MCWEB_LOCAL_CONFIG_PATH="${WORKSPACE}/intentionally-absent-local.yml"
export MCWEB_SECRET_BACKUP_REFERENCE="vault://mcweb/acceptance/versions/v1"
export MCWEB_RECOVERY_EVIDENCE_DIR="${WORKSPACE}/recovery-evidence"
export MCWEB_RECOVERY_EVIDENCE_CLASS="local_acceptance"

create_database_pair() {
  local database="$1"
  [[ "${database}" =~ ^mcweb_acceptance_[a-z]+$ ]] || die "unsafe acceptance database name"
  createdb --maintenance-db=postgres "${database}"
  createdb --maintenance-db=postgres "${database}_cache"
}

use_database() {
  local database="$1"
  [[ "${database}" =~ ^mcweb_acceptance_[a-z]+$ ]] || die "unsafe acceptance database name"
  export MCWEB_DATABASE_NAME="${database}"
  export PGDATABASE="${database}"
  unset DATABASE_URL
}

run_probe() {
  local action="$1"
  MCWEB_ACCEPTANCE_ACTION="${action}" \
    bundle exec rails runner scripts/production-acceptance-probe.rb
}

FRESH_DATABASE="mcweb_acceptance_fresh"
UPGRADE_DATABASE="mcweb_acceptance_upgrade"
RESTORE_DATABASE="mcweb_acceptance_restore"
UPGRADE_BASELINE_VERSION="20260729126000"
[[ -f "db/migrate/${UPGRADE_BASELINE_VERSION}_create_operations_worker_heartbeats.rb" ]] ||
  die "recorded upgrade baseline migration is missing"

phase "fresh-production-database"
create_database_pair "${FRESH_DATABASE}"
use_database "${FRESH_DATABASE}"
bundle exec rails db:prepare
run_probe seed-fresh
run_probe verify-fresh

phase "migration-upgrade"
create_database_pair "${UPGRADE_DATABASE}"
use_database "${UPGRADE_DATABASE}"
VERSION="${UPGRADE_BASELINE_VERSION}" bundle exec rails db:migrate
run_probe seed-upgrade
bundle exec rails db:migrate
bundle exec rails db:prepare
run_probe verify-upgrade

phase "object-storage-fail-closed"
use_database "${FRESH_DATABASE}"
export MCWEB_BACKUP_DIR="${WORKSPACE}/failed-backups"
if MCWEB_BACKUP_ID="unreachable-object-store" \
  MCWEB_S3_ENDPOINT="https://127.0.0.1:1" \
  bash bin/backup
then
  die "backup unexpectedly succeeded with unreachable object storage"
fi

phase "backup-and-verify-only-restore"
export MCWEB_BACKUP_DIR="${WORKSPACE}/backups"
export MCWEB_BACKUP_ID="acceptance-v1"
bash bin/backup
BACKUP_PATH="${MCWEB_BACKUP_DIR}/${MCWEB_BACKUP_ID}"
run_probe delete-primary-object
bash bin/restore --backup "${BACKUP_PATH}" --verify

phase "guarded-restore"
create_database_pair "${RESTORE_DATABASE}"
use_database "${RESTORE_DATABASE}"
if bash bin/restore \
  --backup "${BACKUP_PATH}" \
  --apply \
  --target-database "${RESTORE_DATABASE}" \
  --confirm "RESTORE:not-the-backup-id"
then
  die "restore unexpectedly accepted an invalid confirmation"
fi
bash bin/restore \
  --backup "${BACKUP_PATH}" \
  --apply \
  --target-database "${RESTORE_DATABASE}" \
  --confirm "RESTORE:${MCWEB_BACKUP_ID}"
export MCWEB_S3_BUCKET="${MCWEB_RESTORE_S3_BUCKET}"
bundle exec rails db:prepare
run_probe verify-restored

if bash bin/restore \
  --backup "${BACKUP_PATH}" \
  --apply \
  --target-database "${RESTORE_DATABASE}" \
  --confirm "RESTORE:${MCWEB_BACKUP_ID}"
then
  die "restore unexpectedly accepted a non-empty target database"
fi

phase "redis-fail-closed"
if REDIS_URL="redis://127.0.0.1:1/0" run_probe verify-restored; then
  die "production probe unexpectedly succeeded with unreachable Redis"
fi

phase "complete"
echo "Production acceptance passed: image build, fresh install, upgrade, S3, Redis, backup, and restore."
