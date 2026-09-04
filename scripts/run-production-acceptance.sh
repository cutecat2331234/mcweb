#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

CURRENT_PHASE="startup"
APP_ROOT=""
WORKSPACE=""
RUNTIME_ROOT=""
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
ACCEPTANCE_RUNNER_TIMEOUT_SECONDS=4200
DATABASE_COMMAND_TIMEOUT_SECONDS=30
DEPENDENCY_PROBE_TIMEOUT_SECONDS=5
DEPENDENCY_PROBE_ATTEMPTS=5
POSTGRES_CONNECT_TIMEOUT_SECONDS=3
POSTGRES_PROBE_TIMEOUT_SECONDS=5
POSTGRES_PROBE_ATTEMPTS=15
readonly DOCKER_INFO_TIMEOUT_SECONDS DOCKER_CONTROL_TIMEOUT_SECONDS
readonly DOCKER_PULL_TIMEOUT_SECONDS COMPOSE_BUILD_TIMEOUT_SECONDS
readonly COMPOSE_WAIT_TIMEOUT_SECONDS COMPOSE_UP_TIMEOUT_SECONDS
readonly COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS COMPOSE_DOWN_TIMEOUT_SECONDS
readonly COMPOSE_LOG_TAIL_LINES
readonly ACCEPTANCE_RUNNER_TIMEOUT_SECONDS DATABASE_COMMAND_TIMEOUT_SECONDS
readonly DEPENDENCY_PROBE_TIMEOUT_SECONDS DEPENDENCY_PROBE_ATTEMPTS
readonly POSTGRES_CONNECT_TIMEOUT_SECONDS POSTGRES_PROBE_TIMEOUT_SECONDS
readonly POSTGRES_PROBE_ATTEMPTS

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

initialize_acceptance_workspace() {
  local candidate

  for command in cat chmod chown cp mkdir openssl realpath; do
    require_command "${command}"
  done

  WORKSPACE="$(realpath --canonicalize-existing /acceptance)"
  RUNTIME_ROOT="$(realpath --canonicalize-existing /var/lib/mcweb)"
  [[ "${WORKSPACE}" == "/acceptance" ]] ||
    die "acceptance initializer workspace must be /acceptance"
  [[ "${RUNTIME_ROOT}" == "/var/lib/mcweb" ]] ||
    die "acceptance initializer runtime root must be /var/lib/mcweb"

  for candidate in ca.crt ca.key minio.csr minio.ext certs; do
    [[ ! -e "${WORKSPACE}/${candidate}" ]] ||
      die "acceptance named volume was not empty at ${candidate}"
  done
  for candidate in image_packs.yml templates; do
    [[ ! -e "${RUNTIME_ROOT}/${candidate}" ]] ||
      die "acceptance runtime volume was not empty at ${candidate}"
  done

  phase "runtime-volume-preparation"
  mkdir -p "${RUNTIME_ROOT}/templates"
  chmod 0750 "${RUNTIME_ROOT}" "${RUNTIME_ROOT}/templates"

  phase "ephemeral-tls"
  mkdir -p "${WORKSPACE}/certs/CAs"
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
    -days 2 \
    -subj "/CN=McWeb acceptance CA" \
    -keyout "${WORKSPACE}/ca.key" \
    -out "${WORKSPACE}/ca.crt" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -sha256 -nodes \
    -subj "/CN=minio" \
    -keyout "${WORKSPACE}/certs/private.key" \
    -out "${WORKSPACE}/minio.csr" >/dev/null 2>&1
  cat > "${WORKSPACE}/minio.ext" <<'EOF'
subjectAltName=DNS:minio,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
EOF
  openssl x509 -req -sha256 -days 2 \
    -in "${WORKSPACE}/minio.csr" \
    -CA "${WORKSPACE}/ca.crt" \
    -CAkey "${WORKSPACE}/ca.key" \
    -CAcreateserial \
    -extfile "${WORKSPACE}/minio.ext" \
    -out "${WORKSPACE}/certs/public.crt" >/dev/null 2>&1
  cp "${WORKSPACE}/ca.crt" "${WORKSPACE}/certs/CAs/acceptance-ca.crt"

  # MinIO runs as an unprivileged uid. Only the ephemeral server key and
  # certificate chain are shared with it; the CA signing key remains 0600.
  chmod 0755 "${WORKSPACE}/certs" "${WORKSPACE}/certs/CAs"
  chmod 0644 \
    "${WORKSPACE}/certs/private.key" \
    "${WORKSPACE}/certs/public.crt" \
    "${WORKSPACE}/certs/CAs/acceptance-ca.crt"
  openssl verify \
    -CAfile "${WORKSPACE}/ca.crt" \
    "${WORKSPACE}/certs/public.crt" >/dev/null
  chown -R 10002:10002 "${WORKSPACE}" "${RUNTIME_ROOT}"
  printf '[acceptance] workspace-init=complete transport=compose-named-volumes\n'
}

run_acceptance_lifecycle() {
  local attempt
  local postgres_ready=0
  local postgres_probe_status="not-run"
  local redis_ready=0
  local redis_probe_status="not-run"
  local minio_ready=0
  local minio_probe_status="not-run"

  for command in bash bundle createdb curl grep pg_dump pg_restore psql realpath ruby seq sleep timeout; do
    require_command "${command}"
  done

  APP_ROOT="$(realpath --canonicalize-existing "${MCWEB_ACCEPTANCE_APP_ROOT:-/workspace}")"
  WORKSPACE="$(realpath --canonicalize-existing "${MCWEB_ACCEPTANCE_WORKSPACE:-/acceptance}")"
  RUNTIME_ROOT="$(realpath --canonicalize-existing /var/lib/mcweb)"
  [[ "${APP_ROOT}" == "/workspace" ]] ||
    die "acceptance runner application root must be /workspace"
  [[ "${WORKSPACE}" == "/acceptance" ]] ||
    die "acceptance runner workspace must be /acceptance"
  [[ "${RUNTIME_ROOT}" == "/var/lib/mcweb" ]] ||
    die "acceptance runner runtime root must be /var/lib/mcweb"
  [[ "${MCWEB_IMAGE_PACKS_PATH:-}" == "/var/lib/mcweb/image_packs.yml" ]] ||
    die "acceptance image pack registry must use the runtime volume"
  [[ "${MCWEB_IMAGE_PACKS_EXAMPLE_PATH:-}" == "/workspace/config/image_packs.yml.example" ]] ||
    die "acceptance image pack example must use the read-only source image"
  [[ "${MCWEB_TEMPLATE_DIR:-}" == "/var/lib/mcweb/templates" ]] ||
    die "acceptance template storage must use the runtime volume"
  [[ -f "${MCWEB_IMAGE_PACKS_EXAMPLE_PATH}" ]] ||
    die "acceptance image pack example is missing from the source image"
  [[ -d "${MCWEB_TEMPLATE_DIR}" && -w "${RUNTIME_ROOT}" &&
      -w "${MCWEB_TEMPLATE_DIR}" ]] ||
    die "acceptance runtime volume is not writable by the runner"
  [[ -f "${WORKSPACE}/ca.crt" ]] || die "acceptance CA is missing from the runner workspace"
  [[ -n "${MCWEB_ACCEPTANCE_POSTGRES_PASSWORD:-}" ]] ||
    die "acceptance PostgreSQL password is missing"
  [[ -n "${MCWEB_ACCEPTANCE_S3_ACCESS_KEY:-}" ]] ||
    die "acceptance S3 access key is missing"
  [[ -n "${MCWEB_ACCEPTANCE_S3_SECRET_KEY:-}" ]] ||
    die "acceptance S3 secret key is missing"
  pg_dump --version | grep -Eq ' 18\.' ||
    die "PostgreSQL 18 client tools are required for the PostgreSQL 18 acceptance service"

  cd "${APP_ROOT}"
  export PGHOST="postgres"
  export PGPORT="5432"
  export PGUSER="postgres"
  export PGPASSWORD="${MCWEB_ACCEPTANCE_POSTGRES_PASSWORD}"
  export PGCONNECT_TIMEOUT="${POSTGRES_CONNECT_TIMEOUT_SECONDS}"
  export REDIS_URL="redis://redis:6379/0"
  export SSL_CERT_FILE="${WORKSPACE}/ca.crt"
  export AWS_CA_BUNDLE="${WORKSPACE}/ca.crt"
  export NO_PROXY="postgres,redis,minio"
  export no_proxy="postgres,redis,minio"

  phase "dependency-endpoints"
  printf '[acceptance] dependency-transport=compose-network postgres=postgres:5432 redis=redis:6379 minio=minio:9000\n'

  phase "postgres-readiness"
  for attempt in $(seq 1 "${POSTGRES_PROBE_ATTEMPTS}"); do
    if run_with_timeout "${POSTGRES_PROBE_TIMEOUT_SECONDS}" \
      psql --dbname=postgres --no-psqlrc --set=ON_ERROR_STOP=1 \
      --command="SELECT 1" >/dev/null 2>&1
    then
      postgres_ready=1
      printf '[acceptance] postgres-readiness=ready method=compose-network-psql attempt=%s\n' \
        "${attempt}"
      break
    else
      postgres_probe_status=$?
    fi

    printf '[acceptance] postgres-readiness=retry attempt=%s status=%s endpoint=postgres:5432\n' \
      "${attempt}" "${postgres_probe_status}" >&2
    if ((attempt < POSTGRES_PROBE_ATTEMPTS)); then
      sleep 1
    fi
  done
  [[ "${postgres_ready}" == "1" ]] ||
    die "PostgreSQL compose-network endpoint did not accept SQL connections at postgres:5432 (status ${postgres_probe_status})"

  phase "redis-readiness"
  for attempt in $(seq 1 "${DEPENDENCY_PROBE_ATTEMPTS}"); do
    if run_with_timeout "${DEPENDENCY_PROBE_TIMEOUT_SECONDS}" \
      ruby -rsocket -e '
        Socket.tcp(ARGV.fetch(0), Integer(ARGV.fetch(1), 10), connect_timeout: 2) do |socket|
          socket.write(["*1", %q($4), "PING", ""].join("\r\n"))
          abort("unexpected Redis response") unless socket.gets == "+PONG\r\n"
        end
      ' redis 6379 >/dev/null 2>&1
    then
      redis_ready=1
      printf '[acceptance] redis-readiness=ready method=compose-network-ping attempt=%s\n' \
        "${attempt}"
      break
    else
      redis_probe_status=$?
    fi

    printf '[acceptance] redis-readiness=retry attempt=%s status=%s endpoint=redis:6379\n' \
      "${attempt}" "${redis_probe_status}" >&2
    if ((attempt < DEPENDENCY_PROBE_ATTEMPTS)); then
      sleep 1
    fi
  done
  [[ "${redis_ready}" == "1" ]] ||
    die "Redis compose-network endpoint did not answer PING at redis:6379 (status ${redis_probe_status})"

  phase "minio-readiness"
  for attempt in $(seq 1 "${DEPENDENCY_PROBE_ATTEMPTS}"); do
    if run_with_timeout "${DEPENDENCY_PROBE_TIMEOUT_SECONDS}" \
      curl --fail --silent --show-error \
      --cacert "${SSL_CERT_FILE}" --connect-timeout 2 --max-time 4 \
      https://minio:9000/minio/health/live >/dev/null 2>&1
    then
      minio_ready=1
      printf '[acceptance] minio-readiness=ready method=compose-network-tls-health attempt=%s\n' \
        "${attempt}"
      break
    else
      minio_probe_status=$?
    fi

    printf '[acceptance] minio-readiness=retry attempt=%s status=%s endpoint=minio:9000\n' \
      "${attempt}" "${minio_probe_status}" >&2
    if ((attempt < DEPENDENCY_PROBE_ATTEMPTS)); then
      sleep 1
    fi
  done
  [[ "${minio_ready}" == "1" ]] ||
    die "MinIO compose-network TLS health check failed at minio:9000 (status ${minio_probe_status})"

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
  export MCWEB_S3_ENDPOINT="https://minio:9000"
  export MCWEB_S3_FORCE_PATH_STYLE="1"
  export MCWEB_BACKUP_S3_BUCKET="mcweb-acceptance-backups"
  export MCWEB_BACKUP_S3_REGION="us-east-1"
  export MCWEB_BACKUP_S3_ACCESS_KEY_ID="${MCWEB_ACCEPTANCE_S3_ACCESS_KEY}"
  export MCWEB_BACKUP_S3_SECRET_ACCESS_KEY="${MCWEB_ACCEPTANCE_S3_SECRET_KEY}"
  export MCWEB_BACKUP_S3_ENDPOINT="https://minio:9000"
  export MCWEB_BACKUP_S3_FORCE_PATH_STYLE="1"
  export MCWEB_BACKUP_S3_PREFIX="acceptance-backups"
  export MCWEB_RESTORE_S3_BUCKET="mcweb-acceptance-restore"
  export MCWEB_RESTORE_S3_REGION="us-east-1"
  export MCWEB_RESTORE_S3_ACCESS_KEY_ID="${MCWEB_ACCEPTANCE_S3_ACCESS_KEY}"
  export MCWEB_RESTORE_S3_SECRET_ACCESS_KEY="${MCWEB_ACCEPTANCE_S3_SECRET_KEY}"
  export MCWEB_RESTORE_S3_ENDPOINT="https://minio:9000"
  export MCWEB_RESTORE_S3_FORCE_PATH_STYLE="1"
  export AWS_EC2_METADATA_DISABLED="true"
  export AWS_MAX_ATTEMPTS="1"
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
    [[ "${database}" =~ ^mcweb_acceptance_[a-z]+$ ]] ||
      die "unsafe acceptance database name"
    run_with_timeout "${DATABASE_COMMAND_TIMEOUT_SECONDS}" \
      createdb --maintenance-db=postgres "${database}" ||
      die "could not create acceptance database ${database}"
    run_with_timeout "${DATABASE_COMMAND_TIMEOUT_SECONDS}" \
      createdb --maintenance-db=postgres "${database}_cache" ||
      die "could not create acceptance database ${database}_cache"
  }

  use_database() {
    local database="$1"
    [[ "${database}" =~ ^mcweb_acceptance_[a-z]+$ ]] ||
      die "unsafe acceptance database name"
    export MCWEB_DATABASE_NAME="${database}"
    export PGDATABASE="${database}"
    unset DATABASE_URL
  }

  run_probe() {
    local action="$1"
    MCWEB_ACCEPTANCE_ACTION="${action}" \
      bundle exec rails runner scripts/production-acceptance-probe.rb
  }

  local fresh_database="mcweb_acceptance_fresh"
  local upgrade_database="mcweb_acceptance_upgrade"
  local restore_database="mcweb_acceptance_restore"
  local upgrade_baseline_version="20260729126000"
  local backup_path
  [[ -f "db/migrate/${upgrade_baseline_version}_create_operations_worker_heartbeats.rb" ]] ||
    die "recorded upgrade baseline migration is missing"

  phase "fresh-production-database"
  create_database_pair "${fresh_database}"
  use_database "${fresh_database}"
  bundle exec rails db:prepare
  [[ -f "${MCWEB_IMAGE_PACKS_PATH}" ]] ||
    die "production boot did not initialize the writable image pack registry"
  [[ -d "${MCWEB_TEMPLATE_DIR}/mcweb-default" ]] ||
    die "production seeds did not install the default template in runtime storage"
  printf '[acceptance] runtime-writes=verified image-packs=ready templates=ready\n'
  run_probe seed-fresh
  run_probe verify-fresh

  phase "migration-upgrade"
  create_database_pair "${upgrade_database}"
  use_database "${upgrade_database}"
  VERSION="${upgrade_baseline_version}" bundle exec rails db:migrate
  run_probe seed-upgrade
  bundle exec rails db:migrate
  bundle exec rails db:prepare
  run_probe verify-upgrade

  phase "object-storage-fail-closed"
  use_database "${fresh_database}"
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
  backup_path="${MCWEB_BACKUP_DIR}/${MCWEB_BACKUP_ID}"
  run_probe delete-primary-object
  bash bin/restore --backup "${backup_path}" --verify

  phase "guarded-restore"
  create_database_pair "${restore_database}"
  use_database "${restore_database}"
  if bash bin/restore \
    --backup "${backup_path}" \
    --apply \
    --target-database "${restore_database}" \
    --confirm "RESTORE:not-the-backup-id"
  then
    die "restore unexpectedly accepted an invalid confirmation"
  fi
  bash bin/restore \
    --backup "${backup_path}" \
    --apply \
    --target-database "${restore_database}" \
    --confirm "RESTORE:${MCWEB_BACKUP_ID}"
  export MCWEB_S3_BUCKET="${MCWEB_RESTORE_S3_BUCKET}"
  bundle exec rails db:prepare
  run_probe verify-restored

  if bash bin/restore \
    --backup "${backup_path}" \
    --apply \
    --target-database "${restore_database}" \
    --confirm "RESTORE:${MCWEB_BACKUP_ID}"
  then
    die "restore unexpectedly accepted a non-empty target database"
  fi

  phase "redis-fail-closed"
  if REDIS_URL="redis://127.0.0.1:1/0" run_probe verify-restored; then
    die "production probe unexpectedly succeeded with unreachable Redis"
  fi

  phase "complete"
  echo "Production data-lifecycle acceptance passed: fresh install, upgrade, S3, Redis, backup, and restore."
}

case "${MCWEB_ACCEPTANCE_EXECUTION_MODE:-}" in
  compose-init)
    initialize_acceptance_workspace
    exit 0
    ;;
  compose-runner)
    run_acceptance_lifecycle
    exit 0
    ;;
  "")
    ;;
  *)
    die "unknown MCWEB_ACCEPTANCE_EXECUTION_MODE"
    ;;
esac

compose_with_timeout() {
  local seconds="$1"
  shift

  run_with_timeout "${seconds}" \
    docker compose --project-name "${PROJECT_NAME}" --file "${COMPOSE_FILE}" "$@"
}

collect_compose_diagnostics() {
  local oneoff_container

  [[ "${COMPOSE_DIAGNOSTICS_READY}" == "1" ]] || return 0

  printf '[acceptance] diagnostics=compose-ps phase=%s\n' "${CURRENT_PHASE}" >&2
  compose_with_timeout "${COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS}" \
    ps --all >&2 || printf '[acceptance] diagnostics=compose-ps-unavailable\n' >&2
  printf '[acceptance] diagnostics=compose-logs phase=%s tail=%s\n' \
    "${CURRENT_PHASE}" "${COMPOSE_LOG_TAIL_LINES}" >&2
  compose_with_timeout "${COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS}" \
    logs --no-color --tail "${COMPOSE_LOG_TAIL_LINES}" >&2 || \
    printf '[acceptance] diagnostics=compose-logs-unavailable\n' >&2

  for oneoff_container in "${PROJECT_NAME}-init" "${PROJECT_NAME}-runner"; do
    printf '[acceptance] diagnostics=container-logs container=%s\n' \
      "${oneoff_container}" >&2
    run_with_timeout "${COMPOSE_DIAGNOSTICS_TIMEOUT_SECONDS}" \
      docker logs --tail "${COMPOSE_LOG_TAIL_LINES}" \
      "${oneoff_container}" >&2 2>/dev/null || true
  done
}

cleanup() {
  local status=$?
  local exit_phase="${CURRENT_PHASE}"

  trap - EXIT INT TERM
  printf '[acceptance] exit phase=%s status=%s\n' "${exit_phase}" "${status}" >&2

  if ((status != 0)); then
    collect_compose_diagnostics
  fi

  if [[ "${COMPOSE_DIAGNOSTICS_READY}" == "1" &&
        "${PROJECT_NAME}" =~ ^mcwebacceptance[0-9]+_[0-9]+$ ]]; then
    run_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
      docker rm --force \
      "${PROJECT_NAME}-init" "${PROJECT_NAME}-runner" >/dev/null 2>&1 || true
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

  printf '[acceptance] exit-complete phase=%s status=%s\n' \
    "${exit_phase}" "${status}" >&2
  exit "${status}"
}

for command in docker grep ruby timeout; do
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

phase "workspace-preparation"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${APP_ROOT}/deploy/acceptance/docker-compose.yml"
PROJECT_NAME="mcwebacceptance$$_${RANDOM}"
DOCKER_ENDPOINT="${DOCKER_HOST:-}"
if [[ -z "${DOCKER_ENDPOINT}" ]]; then
  DOCKER_ENDPOINT="$(
    run_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
      docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true
  )"
fi

docker_endpoint_transport() {
  case "${DOCKER_ENDPOINT}" in
    ""|unix://*)
      printf '%s\n' "local-socket"
      ;;
    tcp://*)
      printf '%s\n' "remote-tcp"
      ;;
    *)
      die "production acceptance requires a Unix or TCP Docker endpoint"
      ;;
  esac
}

[[ "${PROJECT_NAME}" =~ ^mcwebacceptance[0-9]+_[0-9]+$ ]] ||
  die "unsafe Docker Compose project name"
printf '[acceptance] docker-endpoint-transport=%s\n' "$(docker_endpoint_transport)"

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
  if ! run_with_timeout "${DOCKER_PULL_TIMEOUT_SECONDS}" docker pull "${image}" >/dev/null 2>&1; then
    die "${dependency} dependency image pull failed or timed out"
  fi
  printf '[acceptance] dependency-image=%s action=pull-complete\n' "${dependency}"
}

resolved_compose_image() {
  local service="$1"
  local image

  [[ "${service}" =~ ^[a-z0-9_-]+$ ]] ||
    die "unsafe Docker Compose service name"
  if ! image="$(
    compose_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
      config --format json 2>/dev/null |
      MCWEB_ACCEPTANCE_COMPOSE_SERVICE="${service}" ruby -rjson -e '
        service = ENV.fetch("MCWEB_ACCEPTANCE_COMPOSE_SERVICE")
        image = JSON.parse(STDIN.read).dig("services", service, "image")
        valid = image.is_a?(String) &&
          image.match?(/\A[^\u0000-\u0020\u007f]+\z/)
        exit 1 unless valid

        STDOUT.write(image)
      ' 2>/dev/null
  )"
  then
    die "${service} dependency image could not be resolved from Docker Compose configuration"
  fi

  printf '%s\n' "${image}"
}

prepare_acceptance_runner_image() {
  local cached_inputs="${MCWEB_ACCEPTANCE_REQUIRE_CACHED_INPUTS:-0}"
  local runner_base_image

  if [[ "${cached_inputs}" == "1" ]]; then
    [[ -n "${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE:-}" ]] ||
      die "MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE is required when cached inputs are enforced"
    [[ "${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE}" != \
      "mcweb-production-acceptance-base:required" ]] ||
      die "the acceptance runner base image must be supplied explicitly"
    runner_base_image="${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE}"
    pull_dependency_image "acceptance-runner-base" "${runner_base_image}"
  else
    runner_base_image="${PROJECT_NAME}-runner-base:acceptance"

    phase "acceptance-runner-base-build"
    if ! run_with_timeout "${COMPOSE_BUILD_TIMEOUT_SECONDS}" \
      docker build \
        --file deploy/cnb/production-acceptance-dependencies.Dockerfile \
        --tag "${runner_base_image}" \
        .
    then
      die "local acceptance runner base build failed or timed out"
    fi
  fi

  MCWEB_ACCEPTANCE_RUNNER_IMAGE="${PROJECT_NAME}-runner:acceptance"
  export MCWEB_ACCEPTANCE_RUNNER_IMAGE

  phase "acceptance-runner-source-build"
  printf '[acceptance] acceptance-runner-build=context-full-workspace network=none\n'
  if ! run_with_timeout "${COMPOSE_BUILD_TIMEOUT_SECONDS}" \
    docker build \
      --pull=false \
      --network none \
      --build-arg "MCWEB_ACCEPTANCE_RUNNER_BASE=${runner_base_image}" \
      --file deploy/acceptance/runner.Dockerfile \
      --tag "${MCWEB_ACCEPTANCE_RUNNER_IMAGE}" \
      .
  then
    die "local source-baked acceptance runner build failed or timed out"
  fi
  printf '[acceptance] acceptance-runner-image=ready source=baked\n'
}

prepare_dependency_images() {
  local cached_inputs="${MCWEB_ACCEPTANCE_REQUIRE_CACHED_INPUTS:-0}"
  local postgres_image
  local redis_image
  local minio_image

  phase "dependency-image-resolution"
  postgres_image="$(resolved_compose_image postgres)"
  redis_image="$(resolved_compose_image redis)"

  if [[ "${cached_inputs}" != "1" ]]; then
    pull_dependency_image "postgres" "${postgres_image}"
    pull_dependency_image "redis" "${redis_image}"
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

  minio_image="$(resolved_compose_image minio)"
  pull_dependency_image "postgres" "${postgres_image}"
  pull_dependency_image "redis" "${redis_image}"
  pull_dependency_image "minio" "${minio_image}"
}

export MCWEB_ACCEPTANCE_POSTGRES_PASSWORD="acceptance-postgres-password"
export MCWEB_ACCEPTANCE_S3_ACCESS_KEY="mcweb_acceptance_access"
export MCWEB_ACCEPTANCE_S3_SECRET_KEY="mcweb-acceptance-secret-key-000000000000"

cd "${APP_ROOT}"
APP_IMAGE_BUILT=0
if [[ "${MCWEB_ACCEPTANCE_SKIP_APP_IMAGE_BUILD:-0}" != "1" ]]; then
  phase "application-image-build"
  if ! run_with_timeout "${COMPOSE_BUILD_TIMEOUT_SECONDS}" \
    docker build \
      --file deploy/docker/Dockerfile \
      --tag "${PROJECT_NAME}-app:acceptance" \
      .
  then
    die "application image build failed or timed out"
  fi
  APP_IMAGE_BUILT=1
fi

prepare_acceptance_runner_image
prepare_dependency_images
COMPOSE_DIAGNOSTICS_READY=1

phase "acceptance-workspace-init"
if ! compose_with_timeout "${DOCKER_CONTROL_TIMEOUT_SECONDS}" \
  run --rm --no-deps --pull never --name "${PROJECT_NAME}-init" \
  --user 0:0 --cap-add CHOWN \
  --env MCWEB_ACCEPTANCE_EXECUTION_MODE=compose-init \
  acceptance-runner
then
  die "acceptance named-volume initialization failed or timed out"
fi

phase "compose-up"
if ! compose_with_timeout "${COMPOSE_UP_TIMEOUT_SECONDS}" \
  up --detach --no-build --pull never --wait \
  --wait-timeout "${COMPOSE_WAIT_TIMEOUT_SECONDS}" \
  postgres redis minio
then
  die "Docker Compose dependencies did not become healthy before the bounded wait"
fi
printf '[acceptance] compose-up=complete transport=compose-network\n'

phase "compose-network-lifecycle"
if compose_with_timeout "${ACCEPTANCE_RUNNER_TIMEOUT_SECONDS}" \
  run --rm --no-deps --pull never --name "${PROJECT_NAME}-runner" \
  acceptance-runner
then
  printf '[acceptance] compose-runner=complete\n'
else
  runner_status=$?
  die "acceptance runner failed or timed out (status ${runner_status})"
fi

phase "complete"
printf '[acceptance] orchestration=complete cleanup=compose-project-and-volumes\n'
if [[ "${APP_IMAGE_BUILT}" == "1" ]]; then
  echo "Application image build passed; lifecycle probes ran inside the isolated Compose network."
else
  echo "Application image build was skipped here and remains covered by its separate build gate."
fi
