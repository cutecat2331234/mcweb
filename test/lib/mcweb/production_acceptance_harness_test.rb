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
    assert_includes compose, "${MCWEB_ACCEPTANCE_RUNNER_IMAGE:?MCWEB_ACCEPTANCE_RUNNER_IMAGE is required}"
    assert_includes compose, "acceptance_workspace:/acceptance"
    assert_includes compose, "- /acceptance/certs"
    assert_includes compose, "read_only: true"
    assert_includes compose, 'user: "10002:10002"'
    assert_includes compose, "no-new-privileges:true"
    assert_includes compose, "internal: true"
    refute_includes compose, "ports:"
    refute_includes compose, "type: bind"
    refute_includes compose, "env_file:"
    refute_includes compose, "/var/run/docker.sock"
    refute_includes compose, "CNB_TOKEN"
    refute_includes compose, "MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE"
    refute_match(/^\s+CNB_[A-Z0-9_]+:/, compose)
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
    refute_includes script, "mktemp -d"
    refute_includes script, "CNB_BUILD_WORKSPACE"
    refute_includes script, "CNB_RUNNER_IP"
    refute_includes script, "CNB_ACCEPTANCE_SERVICE_HOST"
    assert_includes script, 'case "${DOCKER_ENDPOINT}" in'
    assert_includes script, '""|unix://*)'
    assert_includes script, "tcp://*)"
    assert_includes script, "docker-endpoint-transport=%s"
    assert_includes script, 'WORKSPACE="$(realpath --canonicalize-existing /acceptance)"'
    assert_includes script, "subjectAltName=DNS:minio,DNS:localhost,IP:127.0.0.1"
    assert_includes script, 'chmod 0755 "${WORKSPACE}/certs"'
    assert_includes script, "transport=compose-named-volume"
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE:-}" ]]'
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-}" ]]'
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-}" ]]'
    assert_includes script, '[[ -n "${MCWEB_ACCEPTANCE_MINIO_IMAGE:-}" ]]'
    assert_includes script,
      'pull_dependency_image "acceptance-runner-base" "${runner_base_image}"'
    assert_includes script, 'pull_dependency_image "postgres" "${postgres_image}"'
    assert_includes script, 'pull_dependency_image "redis" "${redis_image}"'
    assert_includes script, 'pull_dependency_image "minio" "${minio_image}"'
    assert_includes script, "up --detach --no-build --pull never --wait"
    assert_includes script, '--wait-timeout "${COMPOSE_WAIT_TIMEOUT_SECONDS}"'
    assert_includes script, "postgres redis minio"
    assert_includes script, "--env MCWEB_ACCEPTANCE_EXECUTION_MODE=compose-init"
    assert_includes script, "--user 0:0 --cap-add CHOWN"
    assert_includes script, 'compose_with_timeout "${ACCEPTANCE_RUNNER_TIMEOUT_SECONDS}"'
    assert_includes script, '--name "${PROJECT_NAME}-runner"'
    assert_includes script, "ps --all"
    assert_includes script, 'logs --no-color --tail "${COMPOSE_LOG_TAIL_LINES}"'
    assert_includes script, 'compose_with_timeout "${COMPOSE_DOWN_TIMEOUT_SECONDS}"'
    assert_includes script, "down --volumes --remove-orphans"
    assert_includes script, "docker rm --force"
    assert_includes script, '"${PROJECT_NAME}-init" "${PROJECT_NAME}-runner"'
    assert_includes script, "deploy/docker/Dockerfile"
    assert_includes script, "bundle exec rails db:prepare"
    assert_includes script, "VERSION=\"${upgrade_baseline_version}\" bundle exec rails db:migrate"
    assert_includes script, "bash bin/backup"
    assert_includes script, "bash bin/restore"
    assert_includes script, "unreachable object storage"
    assert_includes script, "invalid confirmation"
    assert_includes script, "non-empty target database"
    assert_includes script, 'phase "redis-fail-closed"'
    assert_includes script, "MCWEB_ACCEPTANCE_REQUIRE_CACHED_INPUTS"
    assert_includes script, "Application image build was skipped here"
    assert_includes script, "Production data-lifecycle acceptance passed"
    refute_includes script, "Production acceptance passed: image build"
    refute_includes script, "published_port"
    refute_includes script, "MCWEB_ACCEPTANCE_PUBLISH_HOST"
    refute_includes script, "ACCEPTANCE_SERVICE_HOST"
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
    assert_includes script,
      'runner_base_image="${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE}"'
    refute_includes script, "resolved_compose_image acceptance-runner"
    assert_includes script, 'docker pull "${image}" >/dev/null 2>&1'
    assert_includes script, "dependency image could not be resolved from Docker Compose configuration"
    refute_includes script, "${MCWEB_ACCEPTANCE_POSTGRES_IMAGE:-postgres:18.4-trixie}"
    refute_includes script, "${MCWEB_ACCEPTANCE_REDIS_IMAGE:-redis:8.8.1-alpine3.23}"
    assert_includes script, 'export PGCONNECT_TIMEOUT="${POSTGRES_CONNECT_TIMEOUT_SECONDS}"'
    assert_includes script, 'run_with_timeout "${POSTGRES_PROBE_TIMEOUT_SECONDS}"'
    assert_includes script, 'for attempt in $(seq 1 "${POSTGRES_PROBE_ATTEMPTS}")'
    assert_includes script, "method=compose-network-psql"
    assert_includes script, 'export PGHOST="postgres"'
    assert_includes script, 'export MCWEB_DATABASE_HOST="${PGHOST}"'
    assert_includes script, 'export MCWEB_DATABASE_PORT="${PGPORT}"'
    assert_includes script, 'export REDIS_URL="redis://redis:6379/0"'
    assert_includes script, 'export MCWEB_S3_ENDPOINT="https://minio:9000"'
    assert_includes script, 'export MCWEB_BACKUP_S3_ENDPOINT="https://minio:9000"'
    assert_includes script, 'export MCWEB_RESTORE_S3_ENDPOINT="https://minio:9000"'
    assert_includes script, "dependency-transport=compose-network"
    refute_includes script, "exec --no-TTY postgres"
    refute_includes script, "pg_isready"
    refute_includes script, "published-endpoints"
  end

  test "acceptance readiness requires SQL over the compose service DNS" do
    script = File.read(
      Rails.root.join("scripts/run-production-acceptance.sh")
    )
    readiness_match = script.match(
      /phase "postgres-readiness"\n(?<body>.*?)\nexport RAILS_ENV=production/m
    )

    assert_not_nil readiness_match
    readiness = readiness_match[:body]

    assert_equal 1, readiness.scan("postgres_ready=1").length
    assert_includes readiness, "psql --dbname=postgres"
    assert_includes readiness, "method=compose-network-psql"
    assert_includes readiness, "endpoint=postgres:5432"
    refute_includes readiness, "pg_isready"
    refute_includes readiness, "published"
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

  test "CNB builds a source-baked runner from its explicit pipeline base" do
    config = File.read(Rails.root.join(".cnb.yml"))
    script = File.read(
      Rails.root.join("scripts/run-production-acceptance.sh")
    )
    dockerfile = File.read(
      Rails.root.join("deploy/acceptance/runner.Dockerfile")
    )
    production = File.read(
      Rails.root.join("config/environments/production.rb")
    )
    source_build = script.match(
      /phase "acceptance-runner-source-build"\n(?<body>.*?)\n  then/m
    )

    refute_includes config, "name: cache-production-acceptance-runner"
    refute_includes config, "dockerfile: deploy/acceptance/runner.Dockerfile"
    refute_includes config, "name: MCWEB_ACCEPTANCE_RUNNER_IMAGE"
    assert_includes config, "name: verify-production-acceptance-inputs"
    assert_includes config,
      "MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE: ${CNB_PIPELINE_DOCKER_IMAGE}"
    assert_includes config,
      'test -n "${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE:-}"'
    assert_includes config,
      'test "${MCWEB_ACCEPTANCE_RUNNER_BASE_IMAGE}" = "${CNB_PIPELINE_DOCKER_IMAGE}"'
    assert_includes script,
      'die "the acceptance runner base image must be supplied explicitly"'
    assert_includes script,
      '--build-arg "MCWEB_ACCEPTANCE_RUNNER_BASE=${runner_base_image}"'
    assert_includes script,
      "acceptance-runner-build=context-full-workspace network=none"
    assert_not_nil source_build
    assert_includes source_build[:body], "--pull=false"
    assert_includes source_build[:body], "--network none"
    assert_match(/^\s+\.$/, source_build[:body])
    assert_includes dockerfile,
      "ARG MCWEB_ACCEPTANCE_RUNNER_BASE=mcweb-production-acceptance-base:required"
    assert_includes dockerfile, "FROM ${MCWEB_ACCEPTANCE_RUNNER_BASE}"
    assert_includes dockerfile, "COPY --chown=10002:10002 . ."
    assert_includes dockerfile, "USER 10002:10002"
    refute_includes dockerfile, "apt-get"
    refute_includes dockerfile, "bundle install"
    assert_includes production,
      "config.active_record.dump_schema_after_migration = false"
    assert_includes production,
      "config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)"
  end

  test "CNB builds production and test Vite assets in explicit modes" do
    config = File.read(Rails.root.join(".cnb.yml"))

    assert_includes config, "bin/vite build --mode=production"
    assert_includes config, "bin/vite build --mode=test"
    refute_match(/^\h+bin\/vite build\h*$/, config)
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
