# frozen_string_literal: true

require "test_helper"

class ProductionAcceptanceHarnessTest < ActiveSupport::TestCase
  test "acceptance compose pins real isolated dependencies" do
    compose = File.read(
      Rails.root.join("deploy/acceptance/docker-compose.yml")
    )

    assert_includes compose, "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-postgres:18.4-trixie}"
    assert_includes compose, "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-redis:8.8.1-alpine3.23}"
    assert_includes compose, "${MCWEB_ACCEPTANCE_MINIO_IMAGE:-mcweb-acceptance-minio:local}"
    assert_includes compose, "deploy/acceptance/minio.Dockerfile"
    assert_includes compose, "RELEASE.2025-10-15T17-29-55Z"
    assert_operator compose.scan('"${MCWEB_ACCEPTANCE_PUBLISH_HOST:-127.0.0.1}::').length, :>=, 3
    assert_includes compose, "${MCWEB_ACCEPTANCE_CERTS_DIR}:/certs:ro"
  end

  test "acceptance harness is isolated, fail closed, and exercises release lifecycle" do
    script = File.read(
      Rails.root.join("scripts/run-production-acceptance.sh")
    )

    assert_includes script, "set -Eeuo pipefail"
    refute_includes script, "set -x"
    assert_includes script, 'phase "startup"'
    assert_includes script, 'run_with_timeout "${DOCKER_INFO_TIMEOUT_SECONDS}" docker info'
    assert_includes script, 'docker image inspect "${image}"'
    assert_includes script, 'run_with_timeout "${DOCKER_PULL_TIMEOUT_SECONDS}" docker pull "${image}"'
    assert_includes script, "action=reuse-exact"
    assert_includes script, "action=pull-start"
    assert_includes script, "action=pull-complete"
    assert_includes script, "exit phase=%s status=%s"
    assert_includes script, "mktemp -d"
    assert_includes script, 'WORKSPACE_ROOT_INPUT="${CNB_BUILD_WORKSPACE:-${TMPDIR:-/tmp}}"'
    assert_includes script, 'if [[ -n "${CNB_RUNNER_IP:-}" ]]; then'
    assert_includes script, 'CNB_ACCEPTANCE_SERVICE_HOST="${CNB_RUNNER_IP}"'
    assert_includes script, 'MCWEB_ACCEPTANCE_PUBLISH_HOST="0.0.0.0"'
    assert_includes script, 'MCWEB_ACCEPTANCE_PUBLISH_HOST="127.0.0.1"'
    assert_includes script, 'ACCEPTANCE_SERVICE_SAN="IP:${ACCEPTANCE_SERVICE_HOST}"'
    assert_includes script, 'chmod 0755 "${CERTS_DIR}" "${CERTS_DIR}/CAs"'
    assert_includes script, 'chmod 0644 "${CERTS_DIR}/private.key"'
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-}" ]]'
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-}" ]]'
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_MINIO_IMAGE:-}" ]]'
    assert_includes script, 'pull_dependency_image "postgres" "${postgres_image}"'
    assert_includes script, 'pull_dependency_image "redis" "${redis_image}"'
    assert_includes script, 'pull_dependency_image "minio" "${minio_image}"'
    assert_includes script, "up --detach --no-build --pull never --wait"
    assert_includes script, '--wait-timeout "${COMPOSE_WAIT_TIMEOUT_SECONDS}"'
    assert_includes script, "ps --all"
    assert_includes script, 'logs --no-color --tail "${COMPOSE_LOG_TAIL_LINES}"'
    assert_includes script, 'compose_with_timeout "${COMPOSE_DOWN_TIMEOUT_SECONDS}"'
    assert_includes script, "down --volumes --remove-orphans"
    assert_includes script, "deploy/docker/Dockerfile"
    assert_includes script, "bundle exec rails db:prepare"
    assert_includes script, "VERSION=\"${UPGRADE_BASELINE_VERSION}\" bundle exec rails db:migrate"
    assert_includes script, "bash bin/backup"
    assert_includes script, "bash bin/restore"
    assert_includes script, "unreachable object storage"
    assert_includes script, "invalid confirmation"
    assert_includes script, "non-empty target database"
    assert_includes script, 'phase "redis-fail-closed"'
  end

  test "acceptance harness pulls exact images from the resolved compose config" do
    script = File.read(
      Rails.root.join("scripts/run-production-acceptance.sh")
    )

    assert_includes script,
      "compose_with_timeout \"${DOCKER_CONTROL_TIMEOUT_SECONDS}\" \\\n" \
      "      config --format json 2>/dev/null |"
    assert_includes script, 'JSON.parse(STDIN.read).dig("services", service, "image")'
    assert_includes script, 'image.match?(/\A[^\u0000-\u0020\u007f]+\z/)'
    assert_includes script, 'postgres_image="$(resolved_compose_image postgres)"'
    assert_includes script, 'redis_image="$(resolved_compose_image redis)"'
    assert_includes script, 'minio_image="$(resolved_compose_image minio)"'
    assert_includes script, 'docker pull "${image}" >/dev/null 2>&1'
    assert_includes script, "dependency image could not be resolved from Docker Compose configuration"
    refute_includes script, "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-postgres:18.4-trixie}"
    refute_includes script, "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-redis:8.8.1-alpine3.23}"
    assert_includes script, 'export PGCONNECT_TIMEOUT="${POSTGRES_CONNECT_TIMEOUT_SECONDS}"'
    assert_includes script, 'run_with_timeout "${POSTGRES_PROBE_TIMEOUT_SECONDS}"'
    assert_includes script, 'for attempt in $(seq 1 "${POSTGRES_PROBE_ATTEMPTS}")'
    assert_includes script, 'exec --no-TTY postgres'
    assert_includes script, 'pg_isready --host=127.0.0.1 --port=5432'
    assert_includes script, "method=container-pg_isready"
    assert_includes script, "method=published-psql"
    assert_includes script, "container_status=%s published_status=%s"
    assert_includes script, "PostgreSQL readiness probes failed"
    refute_includes script, "PostgreSQL published port did not become reachable"
    refute_includes script, "compose ps postgres"
  end

  test "CNB preserves the full lifecycle stage budget" do
    config = File.read(Rails.root.join(".cnb.yml"))
    lifecycle_stage = Regexp.new(
      "name: run-production-data-lifecycle-acceptance\\n" \
      "\\s+script: bash scripts/run-production-acceptance\\.sh\\n" \
      "\\s+timeout: 90m"
    )

    assert_match lifecycle_stage, config
  end

  test "production probe refuses arbitrary databases and verifies durable state" do
    probe = File.read(
      Rails.root.join("scripts/production-acceptance-probe.rb")
    )

    assert_includes probe, 'DATABASE_PREFIX = "mcweb_acceptance_"'
    assert_includes probe, "Rails.env.production?"
    assert_includes probe, "ActiveStorage::Blob.create_and_upload!"
    assert_includes probe, "blob.service.exist?"
    assert_includes probe, "blob.download == OBJECT_CONTENT"
    assert_includes probe, "Redis.new"
    assert_includes probe, "verify_current_schema!"
  end
end
