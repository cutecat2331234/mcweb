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
  BASH_PROBE_MARKER = "mcweb-bash-ready"

  test "production recovery scripts are valid Bash programs" do
    bash = require_usable_bash
    SCRIPT_NAMES.each do |name|
      path = ROOT.join("bin", name).to_s.tr("\\", "/")
      _stdout, stderr, status = Open3.capture3(bash, "-n", path)

      assert status.success?, "#{name} failed bash -n:\n#{stderr}"
    end
  end

  test "isolated local backup can be verified without touching a database or production path" do
    Dir.mktmpdir("mcweb-recovery-contract") do |directory|
      fake_bin = File.join(directory, "bin")
      backup_root = File.join(directory, "backups")
      storage_root = File.join(directory, "storage")
      config_file = File.join(directory, "mcweb.env")
      FileUtils.mkdir_p([ fake_bin, storage_root ])
      FileUtils.mkdir_p(File.join(storage_root, "objects", "aa"))
      File.binwrite(File.join(storage_root, "objects", "aa", "blob"), "contract object")

      write_executable(
        File.join(fake_bin, "pg_dump"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
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
          if [[ -n "${FAKE_RESTORE_LOG:-}" ]]; then
            printf 'pg_restore %s\\n' "$*" >> "${FAKE_RESTORE_LOG}"
          fi
          if [[ "${1:-}" == "--list" ]]; then
            artifact="${@: -1}"
            [[ -s "${artifact}" ]]
            exit 0
          fi
          [[ "$*" == *"--exit-on-error"* ]]
          [[ -n "${FAKE_RESTORE_STATE:-}" ]]
          : > "${FAKE_RESTORE_STATE}"
        BASH
      )
      write_executable(
        File.join(fake_bin, "psql"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
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
          DATABASE_URL=isolated-contract-database
          MCWEB_DATABASE_PASSWORD=must-not-be-copied
          MCWEB_ACTIVE_STORAGE_SERVICE=local
          MCWEB_LOCAL_STORAGE_ROOT=#{bash_path(storage_root)}
          MCWEB_BACKUP_DIR=#{bash_path(backup_root)}
          MCWEB_SECRET_BACKUP_REFERENCE=vault://mcweb/production/versions/42
        ENV_FILE
      )

      backup_stdout, backup_stderr, backup_status = run_bash(
        "bin/backup",
        fake_bin:,
        environment: {
          "MCWEB_APPLICATION_ROOT" => bash_path(ROOT),
          "MCWEB_CONFIG_FILE" => bash_path(config_file),
          "MCWEB_BACKUP_ID" => "contract-001"
        }
      )
      assert backup_status.success?, "#{backup_stdout}\n#{backup_stderr}"

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
      assert_not_includes JSON.generate(backup_report), "must-not-be-copied"

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
        environment: {
          "MCWEB_CONFIG_FILE" => "/does/not/exist",
          "DATABASE_URL" => "contract_restore",
          "FAKE_RESTORE_STATE" => bash_path(restore_state),
          "FAKE_RESTORE_LOG" => bash_path(restore_log)
        }
      )
      refute overlap_status.success?, overlap_stdout
      assert_includes overlap_stderr, "restore targets must not overlap"
      assert_not File.exist?(restore_state)

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
        environment: {
          "MCWEB_CONFIG_FILE" => "/does/not/exist",
          "DATABASE_URL" => "contract_restore",
          "FAKE_RESTORE_STATE" => bash_path(restore_state),
          "FAKE_RESTORE_LOG" => bash_path(restore_log)
        }
      )
      restore_trace = File.exist?(restore_log) ? File.read(restore_log) : "no fake command trace"
      assert apply_status.success?,
        "exit=#{apply_status.exitstatus}\n#{apply_stdout}\n#{apply_stderr}\n#{restore_trace}"
      assert_path_exists restore_state
      assert_equal(
        "contract object",
        File.binread(File.join(storage_target, "objects", "aa", "blob"))
      )

      evidence_dir = File.join(backup_root, "recovery-evidence")
      reports = Dir[File.join(evidence_dir, "restore-contract-001-*.json")].map do |path|
        JSON.parse(File.binread(path))
      end
      assert_operator reports.size, :>=, 3
      assert reports.any? { |report| report["outcome"] == "failure" }
      assert reports.any? { |report| report["outcome"] == "success" }
      reports.each do |report|
        serialized = JSON.generate(report)
        assert_not_includes serialized, "must-not-be-copied"
        assert_not_includes serialized, "isolated-contract-database"
        assert_equal "mcweb-recovery-evidence-v1", report.fetch("format")
      end

      write_executable(
        File.join(fake_bin, "pg_dump"),
        <<~BASH
          #!/usr/bin/env bash
          set -euo pipefail
          printf '%s\n' 'simulated dump failure with secret must-not-be-copied' >&2
          exit 41
        BASH
      )
      failed_stdout, failed_stderr, failed_status = run_bash(
        "bin/backup",
        fake_bin:,
        environment: {
          "MCWEB_APPLICATION_ROOT" => bash_path(ROOT),
          "MCWEB_CONFIG_FILE" => bash_path(config_file),
          "MCWEB_BACKUP_ID" => "contract-failure"
        }
      )
      refute failed_status.success?, failed_stdout
      assert_includes failed_stderr, "simulated dump failure"
      failure_reports = Dir[
        File.join(backup_root, ".backup-evidence", "backup-contract-failure-*.json")
      ]
      assert_equal 1, failure_reports.size
      failure_report = JSON.parse(File.binread(failure_reports.first))
      assert_equal "failure", failure_report.fetch("outcome")
      assert_equal "database_dump", failure_report.fetch("stage")
      assert_not_includes JSON.generate(failure_report), "must-not-be-copied"
    end
  end

  test "critical backup and release operations are never silently ignored" do
    SCRIPT_NAMES.each do |name|
      source = script(name)

      assert_no_match(/\|\|\s+true\b/, source, "#{name} must not swallow a critical failure")
    end
  end

  test "backup is atomic, checksummed, and never copies plaintext production secrets" do
    source = script("backup")

    assert_no_match(/\bcp\b[^\n]*mcweb\.env/, source)
    assert_includes source, "pg_dump --format=custom"
    assert_includes source, 'PGDATABASE="${DATABASE_URL}" DATABASE_URL=""'
    assert_includes source, 'PGPASSWORD="${MCWEB_DATABASE_PASSWORD:-${PGPASSWORD:-}}"'
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

  test "restore defaults to verification and protects database storage and config targets" do
    source = script("restore")

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
    assert_includes source, "pg_restore --exit-on-error"
    assert_includes source, 'PGDATABASE="${DATABASE_URL}" DATABASE_URL=""'
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
      "pg_restore --exit-on-error"
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

    Open3.capture3(environment, require_usable_bash, "-lc", command)
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
