# frozen_string_literal: true

require "test_helper"
require "open3"
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
    assert_includes dockerfile, 'ENTRYPOINT ["docker-entrypoint"]'
    assert_includes dockerfile, 'CMD ["web"]'
    assert_includes ROOT.join("bin/install").read, "fonts-noto-cjk"
  end

  test "container roles separate one-shot release from replica startup" do
    entrypoint = ROOT.join("bin/docker-entrypoint").read
    release_builder = ROOT.join("bin/build-release").read

    assert_includes entrypoint, "release)"
    assert_includes entrypoint, "./bin/rails db:prepare"
    assert_includes entrypoint, "./bin/rails db:abort_if_pending_migrations"
    assert_includes entrypoint, "./bin/docker-release"
    assert_includes entrypoint, "bundle exec puma -C config/puma.rb"
    assert_includes entrypoint, "bundle exec sidekiq -C config/sidekiq.yml"
    assert_operator entrypoint.index("./bin/rails db:prepare"), :<,
      entrypoint.index("./bin/docker-release")
    refute_match(/rails server then create or migrate/, entrypoint)
    assert_includes release_builder, "bundle exec rails db:prepare"
    refute_match(/db:prepare.*(?:\|\|\s*true|2>\/dev\/null)/, release_builder)
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

  test "native installer provisions the supported Node and npm runtime" do
    installer = ROOT.join("bin/install").read

    assert_includes installer, 'NODE_MAJOR="26"'
    assert_includes installer, "https://deb.nodesource.com/node_${NODE_MAJOR}.x"
    assert_includes installer, "signed-by=${keyring}"
    assert_includes installer, "apt-get install -y nodejs"
    assert_includes installer, "command -v npm"
    assert_includes installer, "major < 22 || (major === 22 && minor < 12)"
    refute_match(/python3-certbot-nginx openssl nodejs/, installer)
  end

  test "compose gates web and worker on migration and dependency health" do
    compose = YAML.safe_load_file(
      ROOT.join("deploy/docker/docker-compose.yml"),
      aliases: true
    )
    services = compose.fetch("services")

    assert_equal [ "release" ], services.dig("mcweb-migrate", "command")
    assert_equal [ "web" ], services.dig("mcweb-web", "command")
    assert_equal [ "worker" ], services.dig("mcweb-worker", "command")

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

  test "Kamal runs the delivered release once before booting web and job roles" do
    hook = ROOT.join(".kamal/hooks/pre-deploy").read
    deploy = ROOT.join("config/deploy.yml").read

    assert_includes hook, 'set -- app exec --primary --roles web --version "$KAMAL_VERSION"'
    assert_includes hook, 'exec bin/kamal "$@" release'
    assert_includes hook, "exit 64"
    assert_includes deploy, "#   cmd: worker"
    refute_includes deploy, "cmd: bundle exec sidekiq"
  end

  test "entrypoint integration covers real command forms and failure ordering" do
    bash = if Gem.win_platform?
      [
        "C:/Program Files/Git/bin/bash.exe",
        "C:/Ruby40-x64/msys64/usr/bin/bash.exe"
      ].find { |candidate| File.file?(candidate) }
    else
      "bash"
    end
    skip "bash is unavailable" unless bash

    stdout, stderr, status = Open3.capture3(
      bash,
      "test/scripts/container_startup_contract_test.sh",
      chdir: ROOT.to_s
    )

    assert status.success?, [ stdout, stderr ].reject(&:empty?).join("\n")
    assert_includes stdout, "container startup contract: PASS"
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
