# frozen_string_literal: true

require "test_helper"

class ProductionAcceptanceHarnessTest < ActiveSupport::TestCase
  test "acceptance compose pins real isolated dependencies" do
    compose = File.read(
      Rails.root.join("deploy/acceptance/docker-compose.yml")
    )

    assert_includes compose, "postgres:18.4-trixie"
    assert_includes compose, "redis:8.8.1-alpine3.23"
    assert_includes compose, "deploy/acceptance/minio.Dockerfile"
    assert_includes compose, "RELEASE.2025-10-15T17-29-55Z"
    assert_operator compose.scan('"127.0.0.1::').length, :>=, 3
    assert_includes compose, "${MCWEB_ACCEPTANCE_CERTS_DIR}:/certs:ro"
  end

  test "acceptance harness is isolated, fail closed, and exercises release lifecycle" do
    script = File.read(
      Rails.root.join("scripts/run-production-acceptance.sh")
    )

    assert_includes script, "mktemp -d"
    assert_includes script, "compose down --volumes --remove-orphans"
    assert_includes script, "deploy/docker/Dockerfile"
    assert_includes script, "bundle exec rails db:prepare"
    assert_includes script, "VERSION=\"${UPGRADE_BASELINE_VERSION}\" bundle exec rails db:migrate"
    assert_includes script, "bash bin/backup"
    assert_includes script, "bash bin/restore"
    assert_includes script, "unreachable object storage"
    assert_includes script, "invalid confirmation"
    assert_includes script, "non-empty target database"
    assert_includes script, "fail-closed Redis dependency"
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
