# frozen_string_literal: true

require "test_helper"
require "yaml"

class Mcweb::DockerProductionContractTest < ActiveSupport::TestCase
  ROOT = Rails.root
  RECEIPT_FONT_PATHS = %w[
    /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
    /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc
  ].freeze

  test "production image is multi-stage and runs as an unprivileged user" do
    dockerfile = ROOT.join("deploy/docker/Dockerfile").read

    assert_match(/^FROM node:26-bookworm-slim AS node$/, dockerfile)
    assert_match(/^FROM ruby:4\.0\.6-slim-bookworm AS build$/, dockerfile)
    assert_match(/^FROM ruby:4\.0\.6-slim-bookworm AS runtime$/, dockerfile)
    assert_match(/^COPY --from=build --chown=mcweb:mcweb \/app \/app$/, dockerfile)
    assert_match(/^USER mcweb$/, dockerfile)
    assert_equal 1, dockerfile.scan("COPY --from=node /usr/local/bin/node /usr/local/bin/node").length
    assert_equal 1,
      dockerfile.scan("COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules").length
    refute_match(%r{^COPY --from=node /usr/local/bin/(?:npm|npx) }, dockerfile)
    assert_includes dockerfile, "ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm"
    assert_includes dockerfile, "ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx"
    assert_includes dockerfile, "node --version && npm --version"
    assert_operator dockerfile.index("USER mcweb"), :<, dockerfile.index("ENTRYPOINT")
    assert_equal 2, dockerfile.scan(/\blibvips42\b/).length
    assert_match(/apt-get install .*fonts-noto-cjk.*libvips42/, dockerfile)
    RECEIPT_FONT_PATHS.each do |path|
      assert_includes dockerfile, "test -f #{path}"
    end
    assert_includes ROOT.join("bin/install").read, "fonts-noto-cjk"
  end

  test "CI and release jobs install and exercise libvips JPEG support" do
    [
      ROOT.join(".github/workflows/ci.yml"),
      ROOT.join(".github/workflows/release.yml")
    ].each do |workflow|
      source = workflow.read

      assert_includes source, "libvips-dev", workflow.to_s
      assert_includes source, "fonts-noto-cjk", workflow.to_s
      assert_includes(
        source,
        "bundle exec ruby scripts/check-libvips-jpeg.rb",
        workflow.to_s
      )
    end

    ci = ROOT.join(".github/workflows/ci.yml").read
    assert_includes ci, "Verify Unicode receipt fonts"
    RECEIPT_FONT_PATHS.each do |path|
      assert_includes ci, "test -f #{path}"
    end
  end

  test "compose gates web and worker on migration and dependency health" do
    compose = YAML.safe_load_file(
      ROOT.join("deploy/docker/docker-compose.yml"),
      aliases: true
    )
    services = compose.fetch("services")

    assert_equal(
      "service_completed_successfully",
      services.dig("mcweb-web", "depends_on", "mcweb-migrate", "condition")
    )
    assert_equal(
      "service_completed_successfully",
      services.dig("mcweb-worker", "depends_on", "mcweb-migrate", "condition")
    )
    assert_equal(
      "service_healthy",
      services.dig("mcweb-web", "depends_on", "clamav", "condition")
    )
    assert_equal(
      "service_healthy",
      services.dig("mcweb-worker", "depends_on", "clamav", "condition")
    )
    assert_equal "clamav/clamav:1.5_base", services.dig("clamav", "image")
    assert_nil services.dig("clamav", "ports")
    assert_includes services.dig("clamav", "volumes"), "clamavdata:/var/lib/clamav"
    assert_equal(
      "${MCWEB_ATTACHMENT_SCANNER:-clamd_tcp}",
      compose.dig("x-mcweb-environment", "MCWEB_ATTACHMENT_SCANNER")
    )
    assert_equal(
      "${MCWEB_CLAMD_HOST:-clamav}",
      compose.dig("x-mcweb-environment", "MCWEB_CLAMD_HOST")
    )
    assert_includes(
      services.dig("mcweb-web", "healthcheck", "test"),
      "http://127.0.0.1:3000/health/ready"
    )
    assert_includes(
      services.dig("mcweb-worker", "healthcheck", "test").join(" "),
      'connection.call("PING")'
    )
    assert_equal(
      "service_healthy",
      services.dig("nginx", "depends_on", "mcweb-web", "condition")
    )
  end

  test "docker context excludes local secrets and mutable runtime data" do
    ignored = ROOT.join(".dockerignore").read.lines.map(&:strip)

    %w[
      .bundle
      .npmrc
      .env
      .env.*
      config/master.key
      config/credentials/*.key
      config/local*.yml
      *.pem
      *.key
      log/*
      storage/*
      tmp/*
      vendor/bundle
    ].each do |entry|
      assert_includes ignored, entry
    end
  end
end
