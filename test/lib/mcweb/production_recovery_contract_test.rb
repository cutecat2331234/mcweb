# frozen_string_literal: true

require "test_helper"
require "open3"
require "fileutils"
require "json"
require "shellwords"
require "tmpdir"

class Mcweb::ProductionRecoveryContractTest < ActiveSupport::TestCase
  ROOT = Rails.root
  SCRIPT_NAMES = %w[backup backup-maintenance restore update rollback].freeze
  DATABASE_CONNECTION_HELPER = ROOT.join("bin", "lib", "postgres-connection")
  BASH_PROBE_MARKER = "mcweb-bash-ready"

  test "production recovery scripts are valid Bash programs" do
    bash = require_usable_bash
    paths = SCRIPT_NAMES.map { |name| ROOT.join("bin", name) } << DATABASE_CONNECTION_HELPER
    paths.each do |program|
      path = program.to_s.tr("\\", "/")
      _stdout, stderr, status = Open3.capture3(bash, "-n", path)

      assert status.success?, "#{program.basename} failed bash -n:\n#{stderr}"
    end
  end

  test "isolated local backup can be verified without touching a database or production path" do
    Dir.mktmpdir("mcweb-recovery-contract") do |directory|
      fake_bin = File.join(directory, "bin")
      backup_root = File.join(directory, "backups")
      storage_root = File.join(directory, "storage")
      config_file = File.join(directory, "mcweb.env")
      database_temp_paths = File.join(directory, "database-temporary-paths")
      database_temp_root = File.join(directory, "database-connection-tmp")
      backup_database_password = "backup-password:#token"
      backup_database_url =
        "postgresql://backup_user:backup-password%3A%23token@backup-db.example.test:5543/contract_source?application_name=backup%20contract&sslmode=require"
      FileUtils.mkdir_p([ fake_bin, storage_root, database_temp_root ])
      FileUtils.mkdir_p(File.join(storage_root, "objects", "aa"))
      File.binwrite(File.join(storage_root, "objects", "aa", "blob"), "contract object")

      write_executable(
        File.join(fake_bin, "assert-database-environment"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail

          fail() {
            printf 'fake database environment contract failed: %s\n' "$1" >&2
            exit 91
          }

          client="${1:-}"
          [[ -n "${client}" ]] || fail client
          shift
          expected_database_argument=""

          case "${FAKE_EXPECT_DATABASE_CONNECTION_MODE}" in
            service)
              [[ "${DATABASE_URL+x}" != "x" ]] || fail DATABASE_URL
              for variable in \
                PGDATABASE PGHOST PGHOSTADDR PGPORT PGUSER PGPASSWORD PGSERVICE
              do
                [[ ! -v "${variable}" ]] || fail "inherited-${variable}"
              done
              [[ -n "${PGSERVICEFILE:-}" && -f "${PGSERVICEFILE}" ]] || fail PGSERVICEFILE
              [[ -n "${PGPASSFILE:-}" && -f "${PGPASSFILE}" ]] || fail PGPASSFILE
              [[ ! -s "${PGPASSFILE}" ]] || fail PGPASSFILE-content
              [[ "${PGSYSCONFDIR:-}" == "${PGSERVICEFILE%/*}" ]] || fail PGSYSCONFDIR
              ruby -e '
                ARGV.each do |path|
                  stat = File.lstat(path)
                  abort unless stat.file? && !stat.symlink? && (stat.mode & 0o777) == 0o600
                end
              ' "${PGSERVICEFILE}" "${PGPASSFILE}" || fail temporary-permissions

              declare -A service_values=()
              service_section_count=0
              while IFS= read -r line || [[ -n "${line}" ]]; do
                case "${line}" in
                  '[mcweb-maintenance]')
                    service_section_count=$((service_section_count + 1))
                    ;;
                  *=*)
                    key="${line%%=*}"
                    service_values["${key}"]="${line#*=}"
                    ;;
                  *)
                    fail service-syntax
                    ;;
                esac
              done < "${PGSERVICEFILE}"
              [[ "${service_section_count}" == "1" ]] || fail service-section
              [[ -z "${service_values[service]+x}" ]] || fail nested-service
              [[ -z "${service_values[servicefile]+x}" ]] || fail nested-servicefile
              [[ "${service_values[dbname]:-}" == "${FAKE_EXPECTED_SERVICE_DBNAME}" ]] || fail service-dbname
              [[ "${service_values[host]:-}" == "${FAKE_EXPECTED_SERVICE_HOST}" ]] || fail service-host
              [[ "${service_values[port]:-}" == "${FAKE_EXPECTED_SERVICE_PORT}" ]] || fail service-port
              [[ "${service_values[user]:-}" == "${FAKE_EXPECTED_SERVICE_USER}" ]] || fail service-user
              [[ "${service_values[password]:-}" == "${FAKE_EXPECTED_SERVICE_PASSWORD}" ]] || fail service-password
              if [[ -n "${FAKE_EXPECTED_SERVICE_APPLICATION_NAME:-}" ]]; then
                [[ "${service_values[application_name]:-}" == "${FAKE_EXPECTED_SERVICE_APPLICATION_NAME}" ]] ||
                  fail service-application-name
              fi
              if [[ -n "${FAKE_EXPECTED_SERVICE_SSLMODE:-}" ]]; then
                [[ "${service_values[sslmode]:-}" == "${FAKE_EXPECTED_SERVICE_SSLMODE}" ]] ||
                  fail service-sslmode
              fi
              if [[ -n "${FAKE_DATABASE_TEMP_PATHS:-}" ]]; then
                ruby -e 'ARGV.each { |path| puts File.expand_path(path) }' \
                  "${PGSERVICEFILE}" "${PGPASSFILE}" >> "${FAKE_DATABASE_TEMP_PATHS}"
              fi
              expected_database_argument="--dbname=service=mcweb-maintenance"
              ;;
            split)
              [[ "${DATABASE_URL+x}" != "x" ]] || fail DATABASE_URL-unset
              [[ "${PGDATABASE:-}" == "${FAKE_EXPECTED_PGDATABASE}" ]] || fail PGDATABASE
              [[ "${PGHOST:-}" == "${FAKE_EXPECTED_PGHOST}" ]] || fail PGHOST
              [[ "${PGPORT:-}" == "${FAKE_EXPECTED_PGPORT}" ]] || fail PGPORT
              [[ "${PGUSER:-}" == "${FAKE_EXPECTED_PGUSER}" ]] || fail PGUSER
              [[ "${PGPASSWORD:-}" == "${FAKE_EXPECTED_PGPASSWORD}" ]] || fail PGPASSWORD
              [[ "${PGSERVICE+x}" != "x" ]] || fail PGSERVICE
              [[ "${PGSERVICEFILE+x}" != "x" ]] || fail PGSERVICEFILE
              [[ "${PGSYSCONFDIR+x}" != "x" ]] || fail PGSYSCONFDIR
              for variable in PGHOSTADDR PGPASSFILE
              do
                [[ ! -v "${variable}" ]] || fail "inherited-${variable}"
              done
              if [[ "${client}" == "pg_restore" ]]; then
                expected_database_argument="--dbname=${FAKE_EXPECTED_PGDATABASE}"
              fi
              ;;
            *)
              fail connection-mode
              ;;
          esac

          [[ "${PGCONNECT_TIMEOUT:-}" == "${FAKE_EXPECTED_PGCONNECT_TIMEOUT}" ]] ||
            fail PGCONNECT_TIMEOUT
          [[ "${PGSSLMODE:-}" == "${FAKE_EXPECTED_PGSSLMODE}" ]] || fail PGSSLMODE
          [[ "${PGSSLROOTCERT:-}" == "${FAKE_EXPECTED_PGSSLROOTCERT}" ]] || fail PGSSLROOTCERT
          [[ "${PGREQUIREAUTH:-}" == "${FAKE_EXPECTED_PGREQUIREAUTH}" ]] || fail PGREQUIREAUTH
          [[ "${PGCHANNELBINDING:-}" == "${FAKE_EXPECTED_PGCHANNELBINDING}" ]] ||
            fail PGCHANNELBINDING

          database_argument_count=0
          for argument in "$@"; do
            [[ "${argument}" != *"${FAKE_FORBIDDEN_ARGV_FRAGMENT}"* ]] ||
              fail credential-in-argv
            case "${argument}" in
              --dbname=*)
                [[ -n "${expected_database_argument}" && "${argument}" == "${expected_database_argument}" ]] ||
                  fail database-argument
                database_argument_count=$((database_argument_count + 1))
                ;;
              --dbname)
                fail database-argument
                ;;
            esac
          done
          if [[ -n "${expected_database_argument}" ]]; then
            [[ "${database_argument_count}" == "1" ]] || fail database-argument-count
          else
            [[ "${database_argument_count}" == "0" ]] || fail database-argument-count
          fi
        BASH
      )

      write_executable(
        File.join(fake_bin, "pg_dump"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          if [[ "${FAKE_ASSERT_DATABASE_ENVIRONMENT:-0}" == "1" ]]; then
            assert-database-environment pg_dump "$@"
          fi
          output=""
          for argument in "$@"; do
            case "${argument}" in
              --file=*) output="${argument#--file=}" ;;
            esac
          done
          [[ -n "${output}" ]]
          printf 'isolated custom dump' > "${output}"
        BASH
      )
      write_executable(
        File.join(fake_bin, "pg_restore"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          if [[ "${1:-}" == "--list" ]]; then
            artifact="${@: -1}"
            [[ -s "${artifact}" ]]
            if [[ -n "${FAKE_RESTORE_LOG:-}" ]]; then
              printf '%s\\n' 'pg_restore list-ok' >> "${FAKE_RESTORE_LOG}"
            fi
            exit 0
          fi

          if [[ "${FAKE_ASSERT_DATABASE_ENVIRONMENT:-0}" == "1" ]]; then
            assert-database-environment pg_restore "$@"
          fi

          exit_on_error=0
          for argument in "$@"; do
            case "${argument}" in
              --exit-on-error)
                exit_on_error=1
                ;;
            esac
          done
          [[ "${exit_on_error}" == "1" ]]
          [[ -n "${FAKE_RESTORE_STATE:-}" ]]
          : > "${FAKE_RESTORE_STATE}"
          if [[ -n "${FAKE_RESTORE_LOG:-}" ]]; then
            printf '%s\\n' 'pg_restore direct-restore environment-ok' >> "${FAKE_RESTORE_LOG}"
          fi
        BASH
      )
      write_executable(
        File.join(fake_bin, "psql"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          if [[ "${FAKE_ASSERT_DATABASE_ENVIRONMENT:-0}" == "1" ]]; then
            assert-database-environment psql "$@"
          fi
          query="${@: -1}"
          if [[ -n "${FAKE_RESTORE_LOG:-}" ]]; then
            printf 'psql %s\\n' "${query}" >> "${FAKE_RESTORE_LOG}"
          fi
          case "${query}" in
            *"current_database"*)
              printf '%s\\n' 'contract_restore'
              ;;
            *"pg_event_trigger"*)
              printf '%s\\n' '0'
              ;;
            *"schema_migrations"*)
              [[ -f "${FAKE_RESTORE_STATE}" ]]
              printf '%s\\n' '3'
              ;;
            *)
              exit 41
              ;;
          esac
        BASH
      )

      File.write(
        config_file,
        <<~ENV_FILE
          RAILS_ENV=test
          DATABASE_URL='#{backup_database_url}'
          MCWEB_DATABASE_PASSWORD=must-not-be-copied
          MCWEB_ACTIVE_STORAGE_SERVICE=local
          MCWEB_LOCAL_STORAGE_ROOT=#{bash_path(storage_root)}
          MCWEB_BACKUP_DIR=#{bash_path(backup_root)}
          MCWEB_SECRET_BACKUP_REFERENCE=vault://mcweb/production/versions/42
        ENV_FILE
      )

      hostile_libpq_environment = {
        "PGDATABASE" => "hostile-inherited-database",
        "PGHOST" => "hostile-inherited-host",
        "PGHOSTADDR" => "203.0.113.9",
        "PGPASSWORD" => "hostile-inherited-password",
        "PGPASSFILE" => "/hostile/inherited/pgpass",
        "PGSERVICE" => "hostile-inherited-service",
        "PGSERVICEFILE" => "/hostile/inherited/service",
        "PGSYSCONFDIR" => "/hostile/inherited/system",
        "PGOPTIONS" => "-c statement_timeout=120000",
        "PGCONNECT_TIMEOUT" => "7",
        "PGSSLMODE" => "verify-full",
        "PGSSLROOTCERT" => "/trusted/postgresql/root.crt",
        "PGREQUIREAUTH" => "scram-sha-256",
        "PGCHANNELBINDING" => "require",
        "FAKE_EXPECTED_PGCONNECT_TIMEOUT" => "7",
        "FAKE_EXPECTED_PGSSLMODE" => "verify-full",
        "FAKE_EXPECTED_PGSSLROOTCERT" => "/trusted/postgresql/root.crt",
        "FAKE_EXPECTED_PGREQUIREAUTH" => "scram-sha-256",
        "FAKE_EXPECTED_PGCHANNELBINDING" => "require"
      }
      backup_database_contract_environment = hostile_libpq_environment.merge(
        "MCWEB_APPLICATION_ROOT" => bash_path(ROOT),
        "MCWEB_CONFIG_FILE" => bash_path(config_file),
        "FAKE_ASSERT_DATABASE_ENVIRONMENT" => "1",
        "FAKE_EXPECT_DATABASE_CONNECTION_MODE" => "service",
        "FAKE_EXPECTED_SERVICE_DBNAME" => "contract_source",
        "FAKE_EXPECTED_SERVICE_HOST" => "backup-db.example.test",
        "FAKE_EXPECTED_SERVICE_PORT" => "5543",
        "FAKE_EXPECTED_SERVICE_USER" => "backup_user",
        "FAKE_EXPECTED_SERVICE_PASSWORD" => backup_database_password,
        "FAKE_EXPECTED_SERVICE_APPLICATION_NAME" => "backup contract",
        "FAKE_EXPECTED_SERVICE_SSLMODE" => "require",
        "FAKE_FORBIDDEN_ARGV_FRAGMENT" => backup_database_password,
        "FAKE_DATABASE_TEMP_PATHS" => bash_path(database_temp_paths),
        "TMPDIR" => bash_path(database_temp_root)
      )
      backup_stdout, backup_stderr, backup_status = run_bash(
        "bin/backup",
        fake_bin:,
        environment: backup_database_contract_environment.merge(
          "MCWEB_BACKUP_ID" => "contract-001"
        )
      )
      assert backup_status.success?, "#{backup_stdout}\n#{backup_stderr}"
      [ "must-not-be-copied", backup_database_url, backup_database_password ].each do |credential|
        assert_not_includes "#{backup_stdout}\n#{backup_stderr}", credential
      end
      assert_database_temporary_files_removed(database_temp_paths, database_temp_root)

      backup = File.join(backup_root, "contract-001")
      assert_path_exists File.join(backup, "database.dump")
      assert_path_exists File.join(backup, "active_storage.tar.gz")
      assert_path_exists File.join(backup, "active_storage_files.sha256")
      assert_path_exists File.join(backup, "backup-manifest.json")
      assert_path_exists File.join(backup, "SHA256SUMS")
      assert_not File.exist?(File.join(backup, "mcweb.env"))
      assert_not_includes File.read(File.join(backup, "configuration.env")), "must-not-be-copied"
      backup_reports = Dir[File.join(backup_root, ".backup-evidence", "backup-contract-001-*.json")]
      assert_equal 1, backup_reports.size
      backup_report = JSON.parse(File.binread(backup_reports.first))
      assert_equal "mcweb-backup-run-evidence-v1", backup_report.fetch("format")
      assert_equal "success", backup_report.fetch("outcome")
      [ "must-not-be-copied", backup_database_url, backup_database_password ].each do |credential|
        assert_not_includes JSON.generate(backup_report), credential
      end

      restore_stdout, restore_stderr, restore_status = run_bash(
        "bin/restore",
        fake_bin:,
        arguments: [ "--backup", bash_path(backup) ],
        environment: { "MCWEB_CONFIG_FILE" => "/does/not/exist" }
      )
      assert restore_status.success?, "#{restore_stdout}\n#{restore_stderr}"
      assert_includes restore_stdout, "Dry run only"

      restore_state = File.join(directory, "restore-applied")
      restore_log = File.join(directory, "restore.log")
      storage_target = File.join(directory, "restored-storage")
      overlapping_target = File.join(directory, "overlapping-target")
      clean_database_environment = {
        "DATABASE_URL" => nil,
        "PGDATABASE" => nil,
        "PGHOST" => nil,
        "PGPORT" => nil,
        "PGUSER" => nil,
        "PGPASSWORD" => nil,
        "PGPASSFILE" => nil,
        "PGSERVICE" => nil,
        "PGSERVICEFILE" => nil,
        "PGSYSCONFDIR" => nil,
        "PGHOSTADDR" => nil,
        "PGOPTIONS" => nil,
        "PGAPPNAME" => nil,
        "PGCONNECT_TIMEOUT" => nil,
        "PGSSLMODE" => nil,
        "PGSSLKEY" => nil,
        "PGSSLCERT" => nil,
        "PGSSLROOTCERT" => nil,
        "PGREQUIREAUTH" => nil,
        "PGCHANNELBINDING" => nil,
        "PGGSSENCMODE" => nil,
        "MCWEB_DATABASE_NAME" => nil,
        "MCWEB_DATABASE_HOST" => nil,
        "MCWEB_DATABASE_PORT" => nil,
        "MCWEB_DATABASE_USERNAME" => nil,
        "MCWEB_DATABASE_PASSWORD" => nil
      }
      overlap_stdout, overlap_stderr, overlap_status = run_bash(
        "bin/restore",
        fake_bin:,
        arguments: [
          "--backup", bash_path(backup),
          "--apply",
          "--target-database", "contract_restore",
          "--storage-target", bash_path(overlapping_target),
          "--restore-config",
          "--config-target", bash_path(overlapping_target),
          "--confirm", "RESTORE:contract-001"
        ],
        environment: clean_database_environment.merge(hostile_libpq_environment).merge(
          "MCWEB_CONFIG_FILE" => "/does/not/exist",
          "MCWEB_DATABASE_NAME" => "contract_restore",
          "FAKE_RESTORE_STATE" => bash_path(restore_state),
          "FAKE_RESTORE_LOG" => bash_path(restore_log)
        )
      )
      refute overlap_status.success?, overlap_stdout
      assert_includes overlap_stderr, "restore targets must not overlap"
      assert_not File.exist?(restore_state)

      database_url_password = "restore password:#token"
      credential_database_url =
        "host='db.example.test' port='5544' dbname='contract_restore' user='contract_user' password='#{database_url_password}' application_name='restore contract' sslmode='require'"
      apply_stdout, apply_stderr, apply_status = run_bash(
        "bin/restore",
        fake_bin:,
        arguments: [
          "--backup", bash_path(backup),
          "--apply",
          "--target-database", "contract_restore",
          "--storage-target", bash_path(storage_target),
          "--confirm", "RESTORE:contract-001"
        ],
        environment: clean_database_environment.merge(hostile_libpq_environment).merge(
          "MCWEB_CONFIG_FILE" => "/does/not/exist",
          "DATABASE_URL" => credential_database_url,
          "FAKE_RESTORE_STATE" => bash_path(restore_state),
          "FAKE_RESTORE_LOG" => bash_path(restore_log),
          "FAKE_ASSERT_DATABASE_ENVIRONMENT" => "1",
          "FAKE_EXPECT_DATABASE_CONNECTION_MODE" => "service",
          "FAKE_EXPECTED_SERVICE_DBNAME" => "contract_restore",
          "FAKE_EXPECTED_SERVICE_HOST" => "db.example.test",
          "FAKE_EXPECTED_SERVICE_PORT" => "5544",
          "FAKE_EXPECTED_SERVICE_USER" => "contract_user",
          "FAKE_EXPECTED_SERVICE_PASSWORD" => database_url_password,
          "FAKE_EXPECTED_SERVICE_APPLICATION_NAME" => "restore contract",
          "FAKE_EXPECTED_SERVICE_SSLMODE" => "require",
          "FAKE_FORBIDDEN_ARGV_FRAGMENT" => database_url_password,
          "FAKE_DATABASE_TEMP_PATHS" => bash_path(database_temp_paths),
          "TMPDIR" => bash_path(database_temp_root)
        )
      )
      restore_trace = File.exist?(restore_log) ? File.read(restore_log) : "no fake command trace"
      assert apply_status.success?,
        "exit=#{apply_status.exitstatus}\n#{apply_stdout}\n#{apply_stderr}\n#{restore_trace}"
      assert_includes restore_trace, "pg_restore direct-restore environment-ok"
      assert_database_temporary_files_removed(database_temp_paths, database_temp_root)
      [ credential_database_url, database_url_password ].each do |credential|
        assert_not_includes [ apply_stdout, apply_stderr, restore_trace ].join("\n"), credential
      end
      assert_path_exists restore_state
      assert_equal(
        "contract object",
        File.binread(File.join(storage_target, "objects", "aa", "blob"))
      )

      mcweb_restore_state = File.join(directory, "mcweb-restore-applied")
      mcweb_restore_log = File.join(directory, "mcweb-restore.log")
      mcweb_storage_target = File.join(directory, "mcweb-restored-storage")
      mcweb_database_password = "mcweb-database-password"
      mcweb_stdout, mcweb_stderr, mcweb_status = run_bash(
        "bin/restore",
        fake_bin:,
        arguments: [
          "--backup", bash_path(backup),
          "--apply",
          "--target-database", "contract_restore",
          "--storage-target", bash_path(mcweb_storage_target),
          "--confirm", "RESTORE:contract-001"
        ],
        environment: clean_database_environment.merge(hostile_libpq_environment).merge(
          "MCWEB_CONFIG_FILE" => "/does/not/exist",
          "MCWEB_DATABASE_NAME" => "contract_restore",
          "MCWEB_DATABASE_HOST" => "db.internal.example",
          "MCWEB_DATABASE_PORT" => "5544",
          "MCWEB_DATABASE_USERNAME" => "restore_operator",
          "MCWEB_DATABASE_PASSWORD" => mcweb_database_password,
          "FAKE_RESTORE_STATE" => bash_path(mcweb_restore_state),
          "FAKE_RESTORE_LOG" => bash_path(mcweb_restore_log),
          "FAKE_ASSERT_DATABASE_ENVIRONMENT" => "1",
          "FAKE_EXPECT_DATABASE_CONNECTION_MODE" => "split",
          "FAKE_EXPECTED_PGDATABASE" => "contract_restore",
          "FAKE_EXPECTED_PGHOST" => "db.internal.example",
          "FAKE_EXPECTED_PGPORT" => "5544",
          "FAKE_EXPECTED_PGUSER" => "restore_operator",
          "FAKE_EXPECTED_PGPASSWORD" => mcweb_database_password,
          "FAKE_FORBIDDEN_ARGV_FRAGMENT" => mcweb_database_password
        )
      )
      mcweb_restore_trace = if File.exist?(mcweb_restore_log)
        File.read(mcweb_restore_log)
      else
        "no fake command trace"
      end
      assert mcweb_status.success?,
        "exit=#{mcweb_status.exitstatus}\n#{mcweb_stdout}\n#{mcweb_stderr}\n#{mcweb_restore_trace}"
      assert_includes mcweb_restore_trace, "pg_restore direct-restore environment-ok"
      assert_not_includes(
        [ mcweb_stdout, mcweb_stderr, mcweb_restore_trace ].join("\n"),
        mcweb_database_password
      )
      assert_path_exists mcweb_restore_state

      evidence_dir = File.join(backup_root, "recovery-evidence")
      reports = Dir[File.join(evidence_dir, "restore-contract-001-*.json")].map do |path|
        JSON.parse(File.binread(path))
      end
      assert_equal 4, reports.size
      assert_equal(
        { [ "apply", "failure" ] => 1, [ "apply", "success" ] => 2, [ "verify", "success" ] => 1 },
        reports.map { |report| [ report.fetch("mode"), report.fetch("outcome") ] }.tally
      )
      reports.each do |report|
        serialized = JSON.generate(report)
        [
          "must-not-be-copied",
          "isolated-contract-database",
          backup_database_url,
          backup_database_password,
          credential_database_url,
          database_url_password,
          mcweb_database_password
        ].each do |credential|
          assert_not_includes serialized, credential
        end
        assert_equal "mcweb-recovery-evidence-v1", report.fetch("format")
      end

      write_executable(
        File.join(fake_bin, "pg_dump"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          assert-database-environment pg_dump "$@"
          printf '%s\n' 'simulated dump failure' >&2
          exit 41
        BASH
      )
      failed_stdout, failed_stderr, failed_status = run_bash(
        "bin/backup",
        fake_bin:,
        environment: backup_database_contract_environment.merge(
          "MCWEB_BACKUP_ID" => "contract-failure"
        )
      )
      refute failed_status.success?, failed_stdout
      assert_includes failed_stderr, "simulated dump failure"
      [ "must-not-be-copied", backup_database_url, backup_database_password ].each do |credential|
        assert_not_includes "#{failed_stdout}\n#{failed_stderr}", credential
      end
      assert_database_temporary_files_removed(database_temp_paths, database_temp_root)
      failure_reports = Dir[
        File.join(backup_root, ".backup-evidence", "backup-contract-failure-*.json")
      ]
      assert_equal 1, failure_reports.size
      failure_report = JSON.parse(File.binread(failure_reports.first))
      assert_equal "failure", failure_report.fetch("outcome")
      assert_equal "database_dump", failure_report.fetch("stage")
      [ "must-not-be-copied", backup_database_url, backup_database_password ].each do |credential|
        assert_not_includes JSON.generate(failure_report), credential
      end
    end
  end

  test "critical backup and release operations are never silently ignored" do
    sources = SCRIPT_NAMES.to_h { |name| [ name, script(name) ] }
    sources["postgres-connection"] = database_connection_helper
    sources.each do |name, source|

      assert_no_match(/\|\|\s+true\b/, source, "#{name} must not swallow a critical failure")
    end
  end

  test "backup is atomic, checksummed, and never copies plaintext production secrets" do
    source = script("backup")
    connection_helper = database_connection_helper

    assert_no_match(/\bcp\b[^\n]*mcweb\.env/, source)
    assert_includes source, "pg_dump --format=custom"
    assert_includes source, 'source "${APP_ROOT}/bin/lib/postgres-connection"'
    assert_includes source, "mcweb_prepare_database_connection"
    assert_includes connection_helper, "PG::Connection.conninfo_parse"
    assert_includes connection_helper, '--dbname="service=${MCWEB_DATABASE_SERVICE_NAME}"'
    assert_includes connection_helper, 'PGPASSWORD="${pg_password}"'
    assert_no_match(/PGDATABASE=.*DATABASE_URL/, source)
    assert_no_match(/PGDATABASE=.*DATABASE_URL/, connection_helper)
    assert_includes source, "pg_restore --list"
    assert_includes source, "mcweb.env.gpg"
    assert_includes source, "MCWEB_BACKUP_GPG_RECIPIENT"
    assert_includes source, "MCWEB_SECRET_BACKUP_REFERENCE"
    assert_includes source, "/versions/IMMUTABLE_ID"
    assert_includes source, "active_storage_objects.ndjson"
    assert_includes source, "active_storage.tar.gz"
    assert_includes source, "active_storage_files.sha256"
    assert_includes source, "--owner=0 --group=0"
    assert_includes source, "--hard-dereference"
    assert_includes source, ".active-storage-snapshot."
    assert_includes source, "must not be inside MCWEB_LOCAL_STORAGE_ROOT"
    assert_includes source, "must not be inside MCWEB_BACKUP_DIR"
    assert_includes source, "scripts/object-storage-archive.rb snapshot"
    assert_includes source, "MCWEB_BACKUP_S3_BUCKET"
    assert_includes source, 'format: "mcweb-backup-v2"'
    assert_includes source, 'inventory_format: "mcweb-object-snapshot-v1"'
    assert_includes source, "MCWEB_BACKUP_S3_BUCKET must differ from MCWEB_S3_BUCKET"
    assert_includes source, "backup-manifest.json"
    assert_includes source, "SHA256SUMS"
    assert_includes source,
      'mv --no-clobber --no-target-directory "${staging}" "${target}"'

    safe_configuration = source
      .slice(source.index("local -a safe_keys=(")...source.index("write_secret_configuration_artifact()"))

    %w[
      SECRET_KEY_BASE
      LOCKBOX_MASTER_KEY
      MCWEB_DATABASE_PASSWORD
      MCWEB_SMTP_PASSWORD
      MCWEB_S3_ACCESS_KEY_ID
      MCWEB_S3_SECRET_ACCESS_KEY
      MCWEB_S3_SESSION_TOKEN
      MCWEB_BACKUP_S3_ACCESS_KEY_ID
      MCWEB_BACKUP_S3_SECRET_ACCESS_KEY
      MCWEB_BACKUP_S3_SESSION_TOKEN
      MCWEB_RESTORE_S3_ACCESS_KEY_ID
      MCWEB_RESTORE_S3_SECRET_ACCESS_KEY
      MCWEB_RESTORE_S3_SESSION_TOKEN
      REDIS_URL
      RAILS_INBOUND_EMAIL_PASSWORD
    ].each do |secret_name|
      assert_not_includes safe_configuration, secret_name
    end
  end

  test "backup accepts only credential-free HTTPS S3 origins in non-secret configuration" do
    Dir.mktmpdir("mcweb-s3-endpoint-contract") do |directory|
      fake_bin = File.join(directory, "bin")
      backup_root = File.join(directory, "backups")
      storage_root = File.join(directory, "storage")
      config_file = File.join(directory, "mcweb.env")
      FileUtils.mkdir_p([ fake_bin, storage_root ])
      File.binwrite(File.join(storage_root, "blob"), "contract object")

      write_executable(
        File.join(fake_bin, "pg_dump"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          for argument in "$@"; do
            case "${argument}" in
              --file=*) printf 'isolated custom dump' > "${argument#--file=}" ;;
            esac
          done
        BASH
      )
      write_executable(
        File.join(fake_bin, "pg_restore"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          [[ "${1:-}" == "--list" ]]
          [[ -s "${@: -1}" ]]
        BASH
      )
      File.write(
        config_file,
        <<~ENV_FILE
          RAILS_ENV=test
          DATABASE_URL=postgresql:///isolated-contract-database
          MCWEB_ACTIVE_STORAGE_SERVICE=local
          MCWEB_LOCAL_STORAGE_ROOT=#{bash_path(storage_root)}
          MCWEB_BACKUP_DIR=#{bash_path(backup_root)}
          MCWEB_SECRET_BACKUP_REFERENCE=vault://mcweb/production/versions/42
        ENV_FILE
      )

      base_environment = {
        "MCWEB_APPLICATION_ROOT" => bash_path(ROOT),
        "MCWEB_CONFIG_FILE" => bash_path(config_file),
        "MCWEB_S3_ENDPOINT" => nil,
        "MCWEB_BACKUP_S3_ENDPOINT" => nil
      }
      valid_endpoints = [
        "https://minio",
        "https://minio:9000",
        "https://objects.example.internal:9000/",
        "https://127.0.0.1:1",
        "https://[2001:db8::1]:9000/"
      ]
      invalid_endpoints = [
        "http://minio:9000",
        "https://user:password@minio:9000",
        "https://minio:9000/path",
        "https://minio:9000/?query=1",
        "https://minio:9000/#fragment",
        "https://minio:0",
        "https://minio:65536",
        "https://999.1.1.1",
        "https://[not-ip]:9000",
        "https://minio:9000/\t"
      ]

      valid_endpoints.each_with_index do |endpoint, index|
        key = if index == valid_endpoints.length - 1
          "MCWEB_BACKUP_S3_ENDPOINT"
        else
          "MCWEB_S3_ENDPOINT"
        end
        stdout, stderr, status = run_bash(
          "bin/backup",
          fake_bin:,
          environment: base_environment.merge(
            "MCWEB_BACKUP_ID" => "valid-s3-endpoint-#{index}",
            key => endpoint
          )
        )

        assert status.success?, "#{endpoint.inspect}\n#{stdout}\n#{stderr}"
        configuration = File.read(
          File.join(backup_root, "valid-s3-endpoint-#{index}", "configuration.env")
        )
        assert_includes configuration, "#{key}=#{endpoint}"
      end

      invalid_endpoints.each_with_index do |endpoint, index|
        key = if index == invalid_endpoints.length - 1
          "MCWEB_BACKUP_S3_ENDPOINT"
        else
          "MCWEB_S3_ENDPOINT"
        end
        stdout, stderr, status = run_bash(
          "bin/backup",
          fake_bin:,
          environment: base_environment.merge(
            "MCWEB_BACKUP_ID" => "invalid-s3-endpoint-#{index}",
            key => endpoint
          )
        )

        refute status.success?, endpoint.inspect
        assert_includes stderr,
          "refusing a credential-bearing or invalid S3 endpoint in non-secret configuration"
        refute_includes "#{stdout}\n#{stderr}", endpoint
      end
    end
  end

  test "restore defaults to verification and protects database storage and config targets" do
    source = script("restore")
    connection_helper = database_connection_helper

    assert_match(/^MODE="verify"$/, source)
    assert_includes source, '[[ "${CONFIRMATION}" == "RESTORE:${backup_id}" ]]'
    assert_includes source, "--target-database is required"
    assert_includes source, "target database is not empty"
    assert_includes source, "database_user_object_count"
    assert_includes source, "database_required_table_count"
    assert_includes source, "pg_event_trigger"
    assert_includes source, "pg_extension"
    assert_includes source, "validate_absent_target"
    assert_includes source, "must not be inside the backup directory"
    assert_includes source, "restore targets must not overlap"
    assert_includes source, "mv --no-clobber --no-target-directory"
    assert_includes source, "--no-same-owner --no-same-permissions"
    assert_includes source, "plaintext mcweb.env is forbidden"
    assert_includes source, "sha256sum --check --strict SHA256SUMS"
    assert_includes source, "pg_restore --list"
    assert_includes source, "run_pg_restore --exit-on-error"
    assert_includes source, 'source "${APP_ROOT}/bin/lib/postgres-connection"'
    assert_includes connection_helper, "PG::Connection.conninfo_parse"
    assert_includes connection_helper, 'PGSERVICEFILE="${MCWEB_DATABASE_SERVICE_FILE}"'
    assert_includes connection_helper, 'PGPASSFILE="${MCWEB_DATABASE_PASSFILE}"'
    assert_no_match(/PGDATABASE=.*DATABASE_URL/, source)
    assert_no_match(/PGDATABASE=.*DATABASE_URL/, connection_helper)
    assert_includes source, "--single-transaction"
    assert_includes source, "local storage archive contains an unlisted file"
    assert_includes source, "Dry run only: no database, storage, or configuration was changed."
    assert_includes source, "scripts/object-storage-archive.rb verify"
    assert_includes source, "scripts/object-storage-archive.rb restore"
    assert_includes source, "mcweb-recovery-evidence-v1"
    assert_includes source, "EXTERNAL-RESTORE-DRILL:"
    assert_includes source, "legacy private-S3 backup cannot be applied"

    apply_body = source.slice(source.index("apply_restore()")...source.index("parse_arguments()"))
    assert_ordered apply_body,
      "validate_apply_guards",
      "stage_local_storage",
      "scripts/object-storage-archive.rb restore",
      "stage_secret_configuration",
      "run_pg_restore --exit-on-error"
  end

  test "scheduled backup maintenance verifies before bounded retention" do
    source = script("backup-maintenance")
    timer = ROOT.join("config", "templates", "mcweb-backup.timer").read
    service = ROOT.join("config", "templates", "mcweb-backup.service").read

    assert_includes source, "flock --nonblock"
    assert_includes source, "MCWEB_BACKUP_RETENTION_DAYS"
    assert_includes source, "scripts/prune-backups.rb"
    assert_ordered source,
      "flock --nonblock",
      "bin/backup",
      "bin/restore",
      "scripts/prune-backups.rb"
    assert_includes timer, "Persistent=true"
    assert_includes timer, "OnCalendar="
    assert_includes service, "NoNewPrivileges=true"
    assert_includes service, "EnvironmentFile=/etc/mcweb/mcweb.env"
  end

  test "local backup inventory is derived from the completed archive" do
    source = script("backup")
    body = source.slice(
      source.index("write_local_storage_inventory()")...
        source.index("write_backup_manifest()")
    )

    assert_ordered body,
      "tar --create --gzip --hard-dereference",
      'snapshot="$(mktemp -d',
      "tar --extract --gzip",
      'cd "${snapshot}"',
      "active_storage_files.sha256"
  end

  test "update completes backup migration and rollback checks before cutover" do
    source = script("update")
    main_body = source.slice(source.index("main()")..)
    main_contract = source.slice(source.index("# PRE-CUTOVER CONTRACT")..)

    assert_includes source, '[[ "${CONFIRMATION}" == "UPDATE:${release_id}" ]]'
    assert_includes source, 'MCWEB_APPLICATION_ROOT="${CANDIDATE}"'
    assert_includes source, "assert_no_pending_migrations"
    assert_includes source, "scripts/check-stripe-account-binding.rb"
    assert_includes source, "Candidate failed after cutover; switching back"
    assert_includes source, "Update failed while the current release was quiesced"
    assert_includes source, "systemctl is-active --quiet mcweb-web"
    assert_includes source, "systemctl stop mcweb-web mcweb-worker"
    assert_includes source, "flock --nonblock"
    assert_includes source, "MCWEB_RELEASE_LOCK_HELD"
    assert_includes source, "trap recover_failed_update EXIT"
    assert_includes source, "trap 'exit 143' TERM"
    assert_includes source, '"${READY_URL}"'
    assert_ordered main_body,
      "acquire_operation_lock",
      'CURRENT_RELEASE="$(canonical_directory "${CURRENT_LINK}")"'

    assert_ordered main_contract,
      "verify_current_health",
      'preflight_release "${CANDIDATE}"',
      "preflight_stripe_account_binding",
      'check_rollback_compatibility "${CANDIDATE}/bin/rollback" "${CURRENT_RELEASE}"',
      "quiesce_current",
      "preflight_stripe_account_binding",
      "create_backup",
      "run_migrations",
      'preflight_release "${CANDIDATE}"',
      "preflight_stripe_account_binding",
      'check_rollback_compatibility "${CANDIDATE}/bin/rollback" "${CURRENT_RELEASE}"',
      "# CUTOVER CONTRACT",
      'switch_release "${CANDIDATE}"',
      "restart_and_verify",
      'atomic_link "${CURRENT_RELEASE}" "${PREVIOUS_LINK}"'
  end

  test "quick install cannot bypass the candidate update contract" do
    source = ROOT.join("packaging", "quick-install.sh").read
    update_body = source.slice(source.index("run_safe_update()")...source.index("main()"))
    main_body = source.slice(source.index("main()")..)

    assert_includes source, "候选 release 已存在，拒绝覆盖"
    assert_includes source, "--fresh 仅用于没有 current release 的首次安装"
    assert_includes source, '"${RELEASE_DIR}/bin/update"'
    assert_no_match(/\bdb:migrate\b/, source)
    assert_no_match(/ln\s+-sfn\b/, source)
    assert_no_match(/systemctl\s+restart\b/, source)

    assert_ordered update_body,
      '"${RELEASE_DIR}/bin/update"',
      '--release "${RELEASE_DIR}"',
      '--confirm "UPDATE:${RELEASE_VERSION}"'

    assert_ordered main_body,
      '[[ -L "${APP_ROOT}/current" ]]',
      "stage_candidate_release",
      "run_safe_update"
  end

  test "local relay fails closed before candidate migration or restart" do
    source = ROOT.join("scripts", "deploy-local-relay.py").read
    install_body = source.slice(source.index("def install_remote")...source.index("\ndef main"))

    assert_includes install_body, "set -euo pipefail"
    assert_includes install_body, "scripts/check-stripe-account-binding.rb"
    assert_no_match(/\bdb:migrate\b/, install_body)
    assert_no_match(/if\s+!\s+\.\/quick-install\.sh/, install_body)
    assert_no_match(/systemctl\s+restart\b/, install_body)

    assert_ordered install_body,
      "scripts/check-stripe-account-binding.rb",
      "./quick-install.sh",
      "for i in 1 2 3 4 5 6 7 8 9 10"
  end

  test "rollback is check-only by default and preflights before switching traffic" do
    source = script("rollback")
    main_body = source.slice(source.index("main()")..)

    assert_match(/^MODE="check"$/, source)
    assert_includes source, '[[ "${CONFIRMATION}" == "ROLLBACK:${release_id}" ]]'
    assert_includes source, "ActiveRecord::Migration.check_all_pending!"
    assert_includes source, "Database schema was not migrated down."
    assert_no_match(/db:(rollback|migrate:down)/, source)
    assert_includes source, "Rollback target failed after cutover; returning to the original release."
    assert_includes source, "flock --nonblock"
    assert_includes source, "MCWEB_RELEASE_LOCK_HELD"
    assert_includes source, "trap recover_failed_rollback EXIT"
    assert_includes source, "trap 'exit 143' TERM"

    assert_ordered main_body,
      "acquire_operation_lock",
      'CURRENT_RELEASE="$(canonical_directory "${CURRENT_LINK}")"',
      'preflight_target "${TARGET}"',
      '[[ "${MODE}" == "apply" ]] || exit 0',
      'atomic_link "${TARGET}" "${CURRENT_LINK}"',
      "restart_and_verify",
      'atomic_link "${CURRENT_RELEASE}" "${PREVIOUS_LINK}"'
  end

  private

  def database_connection_helper
    DATABASE_CONNECTION_HELPER.read
  end

  def assert_database_temporary_files_removed(path_log, temporary_root)
    assert_path_exists path_log
    paths = File.readlines(path_log, chomp: true).reject(&:empty?).uniq
    assert_operator paths.size, :>=, 2
    paths.each do |path|
      refute File.exist?(path), "temporary database credential file was retained: #{path}"
      refute File.symlink?(path), "temporary database credential symlink was retained: #{path}"
    end
    assert_empty Dir.glob(File.join(temporary_root, ".mcweb-pg-*"))
  end

  def script(name)
    ROOT.join("bin", name).read
  end

  def assert_ordered(source, *tokens)
    cursor = 0

    tokens.each do |token|
      location = source.index(token, cursor)
      assert location, "expected #{token.inspect} after byte #{cursor}"
      cursor = location + token.length
    end
  end

  def bash_path(path)
    normalized = File.expand_path(path).tr("\\", "/")
    normalized.sub(/\A([A-Za-z]):/) { "/#{Regexp.last_match(1).downcase}" }
  end

  def write_executable(path, content)
    File.write(path, content, mode: "wb")
    FileUtils.chmod(0o755, path)
  end

  def run_bash(script, fake_bin:, arguments: [], environment: {})
    command = [
      "export PATH=#{Shellwords.escape(bash_path(fake_bin))}:\"$PATH\"",
      Shellwords.join([ bash_path(ROOT.join(script)), *arguments ])
    ].join("; ")

    isolated_environment = {
      "MCWEB_APPLICATION_ROOT" => nil,
      "MCWEB_BACKUP_EVIDENCE_DIR" => nil,
      "MCWEB_RECOVERY_EVIDENCE_DIR" => nil,
      "MCWEB_RECOVERY_EVIDENCE_CLASS" => nil,
      "MCWEB_RECOVERY_EXTERNAL_DRILL_CONFIRMATION" => nil
    }.merge(environment)
    Open3.capture3(isolated_environment, require_usable_bash, "-lc", command)
  end

  def require_usable_bash
    usable_bash_executable ||
      skip("usable Bash is unavailable; static production recovery contracts still run")
  end

  def usable_bash_executable
    return @usable_bash_executable if defined?(@usable_bash_executable)

    candidates = if Gem.win_platform?
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).flat_map do |directory|
        normalized = directory.delete_prefix('"').delete_suffix('"')
        [ File.join(normalized, "bash.exe"), File.join(normalized, "bash") ]
      end.select { |path| File.file?(path) }
    else
      [ "bash" ]
    end

    @usable_bash_executable = candidates.uniq.find do |candidate|
      stdout, _stderr, status = Open3.capture3(
        candidate,
        "-lc",
        "printf #{Shellwords.escape(BASH_PROBE_MARKER)}"
      )
      status.success? && stdout == BASH_PROBE_MARKER
    rescue Errno::ENOENT
      false
    end
  end
end
