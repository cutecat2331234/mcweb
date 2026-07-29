# frozen_string_literal: true

require "fileutils"
require "find"
require "json"
require "pathname"
require "securerandom"
require "time"
require_relative "../manifest"
require_relative "../generation_coordinator"
require_relative "../owned_data_purger"
require_relative "catalog_store"
require_relative "error"
require_relative "file_health"
require_relative "lifecycle_store"
require_relative "operation_journal"
require_relative "package_archive"
require_relative "package_metadata"
require_relative "setup"

module Mcweb
  module Plugins
    module Marketplace
      class Manager
        ACTIVE_RUNTIME_STATUSES = %w[active degraded].freeze
        UNINSTALL_IDENTITY_ERROR =
          "plugin identity changed or cannot be verified; refresh the plugin list and confirm uninstall again"
        UNINSTALL_DATA_MODES = %w[preserve_data purge_data].freeze
        Result = Data.define(
          :operation_id, :action, :plugin_id, :version, :status,
          :source, :sha256, :recovery_path, :data_mode
        )
        ReconcileResult = Data.define(
          :scanned_count, :synchronized_count, :unavailable_count,
          :finding_count, :findings
        )
        InventoryEntry = Data.define(:manifest, :directory, :manifest_path)

        attr_reader :root, :state_root

        def initialize(root: Mcweb::Plugins.default_root, state_root: nil,
                       reload_callback: nil, runtime_catalog: nil,
                       generation_coordinator: :auto,
                       lifecycle_store: :auto,
                       catalog_store: :auto,
                       ruby_version: RUBY_VERSION, rails_version: Rails.version,
                       clock: -> { Time.now.utc })
          @root = Pathname(root).expand_path.cleanpath
          @state_root = Pathname(state_root || default_state_root).expand_path.cleanpath
          if contained_path?(@state_root, @root)
            raise LifecycleError, "marketplace state directory must remain outside the plugin root"
          end

          @reload_callback = reload_callback || -> { Mcweb::Plugins.reload!(root: @root) }
          @runtime_catalog = runtime_catalog || -> { Mcweb::Plugins.list }
          @generation_coordinator =
            generation_coordinator == :auto ? default_generation_coordinator : generation_coordinator
          @lifecycle_store =
            lifecycle_store == :auto ? default_lifecycle_store : lifecycle_store
          @catalog_store =
            catalog_store == :auto ? default_catalog_store : catalog_store
          @ruby_version = ruby_version.to_s.freeze
          @rails_version = rails_version.to_s.freeze
          @clock = clock
          @journal = OperationJournal.new(path: @state_root.join("operations.jsonl"), clock:)
        end

        def install(package_path:, source:, expected_sha256:, expected_id: nil,
                    allow_downgrade: false, actor: nil, dry_run: false,
                    maintenance_mode: false)
          with_operation(
            :install,
            plugin_id: expected_id,
            actor:,
            dry_run:,
            maintenance_mode:
          ) do |operation_id, context|
            archive = PackageArchive.new(
              path: package_path,
              source: source,
              expected_sha256: expected_sha256
            )
            stage = archive.extract_to(staging_path(operation_id))
            manifest = Manifest.load_file(stage.join(PackageArchive::MANIFEST_NAME))
            metadata = load_package_metadata(stage)
            metadata&.validate!(
              manifest: manifest,
              ruby_version: @ruby_version,
              rails_version: @rails_version
            )
            validate_expected_id!(manifest, expected_id)

            context.merge!(
              plugin_id: manifest.id,
              version: manifest.version,
              source: archive.source.to_h,
              sha256: archive.sha256
            )
            active = active_inventory!
            disabled = disabled_inventory!
            previous_plugins = runtime_plugin_versions
            validate_install_target!(manifest, active:, disabled:)
            validate_version_change!(manifest, active[manifest.id], allow_downgrade:)
            validate_candidate_dependencies!(manifest, active:, disabled:)

            target = managed_path(manifest.id)
            installed = active[manifest.id]
            phase = installed ? :upgrade : :install
            bind_lifecycle_run!(
              context,
              plugin_id: manifest.id,
              action: phase,
              from_version: installed&.manifest&.version,
              to_version: manifest.version
            )
            lifecycle_checkpoint!(
              context,
              "package_validated",
              version: manifest.version,
              package_sha256: archive.sha256
            )
            setup_plan = load_setup_plan(stage, manifest)
            setup_managed = setup_plan || installed&.manifest&.setup
            previous_receipt = read_receipt(manifest.id, strict: installed && setup_managed)
            initial_setup_state = if setup_plan
              installed ? Setup::State.load(previous_receipt["setup"]) : Setup::State.empty
            end
            preserved_setup_state = installed ? previous_receipt["setup"] : nil
            if dry_run
              lifecycle_checkpoint!(
                context,
                "impact_analyzed",
                phase:,
                from_version: installed&.manifest&.version,
                to_version: manifest.version,
                dependency_count: manifest.requires.length,
                setup_step_count: setup_plan&.steps&.length || 0
              )
              next Result.new(
                operation_id:,
                action: phase.to_s,
                plugin_id: manifest.id,
                version: manifest.version,
                status: "validated",
                source: archive.source.to_h,
                sha256: archive.sha256,
                recovery_path: nil,
                data_mode: nil
              )
            end

            with_receipt_rollback(manifest.id) do
              activate_candidate!(stage:, target:, manifest:) do |recovery|
                context[:recovery_path] = state_relative(recovery) if recovery
                with_setup_transaction(
                  plan: setup_plan,
                  phase: phase,
                  state: initial_setup_state,
                  plugin_id: manifest.id,
                  from_version: installed&.manifest&.version,
                  to_version: manifest.version,
                  operation_id:
                ) do |completed_setup_state|
                  lifecycle_checkpoint!(context, "setup_committed") if setup_plan
                  ensure_runtime_state!(manifest, present: true)
                  lifecycle_checkpoint!(context, "runtime_verified")
                  write_receipt(
                    manifest: manifest,
                    status: "active",
                    operation_id: operation_id,
                    source: archive.source.to_h,
                    sha256: archive.sha256,
                    recovery_path: context[:recovery_path],
                    setup_state: completed_setup_state&.to_h || preserved_setup_state,
                    file_manifest: FileHealth.manifest(target),
                    rollback_release: recovery && rollback_release_snapshot(
                      path: recovery,
                      manifest: installed.manifest,
                      receipt: previous_receipt
                    )
                  )
                  lifecycle_checkpoint!(context, "receipt_persisted")
                  generation = coordinate_runtime_generation!(
                    action: phase,
                    target_plugin_id: manifest.id,
                    operation_id:,
                    previous_plugins:,
                    actor: context[:actor]
                  )
                  lifecycle_checkpoint!(
                    context,
                    "generation_activated",
                    number: generation.respond_to?(:number) ? generation.number : nil
                  ) if generation
                  synchronize_catalog_for!(manifest.id, strict: true)
                end
              end
            end
            Result.new(
              operation_id: operation_id,
              action: active.key?(manifest.id) ? "upgrade" : "install",
              plugin_id: manifest.id,
              version: manifest.version,
              status: "active",
              source: archive.source.to_h,
              sha256: archive.sha256,
              recovery_path: context[:recovery_path],
              data_mode: nil
            )
          ensure
            FileUtils.rm_rf(stage) if stage&.exist?
          end
        end

        def disable(plugin_id:, actor: nil, dry_run: false,
                    maintenance_mode: false)
          transition_to_inactive(
            plugin_id:,
            action: :disable,
            actor:,
            dry_run:,
            maintenance_mode:
          )
        end

        def enable(plugin_id:, actor: nil, dry_run: false,
                   maintenance_mode: false)
          with_operation(
            :enable,
            plugin_id:,
            actor:,
            dry_run:,
            maintenance_mode:
          ) do |operation_id, context|
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            previous_plugins = runtime_plugin_versions
            raise LifecycleError, "plugin #{plugin_id} is already active" if active.key?(plugin_id)

            entry = disabled.fetch(plugin_id) do
              raise LifecycleError, "disabled plugin #{plugin_id} was not found"
            end
            ensure_managed_entry!(entry, disabled_path(plugin_id))
            target = managed_path(plugin_id)
            refuse_occupied_target!(target)
            validate_candidate_dependencies!(entry.manifest, active:, disabled: disabled.except(plugin_id))

            receipt = read_receipt(plugin_id, strict: entry.manifest.setup.present?)
            bind_lifecycle_run!(
              context,
              plugin_id:,
              action: :enable,
              from_version: entry.manifest.version,
              to_version: entry.manifest.version
            )
            if dry_run
              lifecycle_checkpoint!(
                context,
                "impact_analyzed",
                phase: :enable,
                to_version: entry.manifest.version
              )
              next lifecycle_preview_result(
                operation_id:,
                action: :enable,
                entry:,
                receipt:
              )
            end
            with_receipt_rollback(plugin_id) do
              move_with_runtime_rollback!(source: entry.directory, destination: target) do
                ensure_runtime_state!(entry.manifest, present: true)
                lifecycle_checkpoint!(context, "runtime_verified")
                context.merge!(plugin_id:, version: entry.manifest.version)
                write_receipt(
                  manifest: entry.manifest,
                  status: "active",
                  operation_id: operation_id,
                  source: receipt["source"],
                  sha256: receipt["sha256"],
                  setup_state: receipt["setup"],
                  file_manifest: receipt["file_manifest"] || FileHealth.manifest(target),
                  data_mode: receipt["data_mode"],
                  rollback_release: receipt["rollback_release"]
                )
                lifecycle_checkpoint!(context, "receipt_persisted")
                generation = coordinate_runtime_generation!(
                  action: :enable,
                  target_plugin_id: plugin_id,
                  operation_id:,
                  previous_plugins:,
                  actor: context[:actor]
                )
                lifecycle_checkpoint!(
                  context,
                  "generation_activated",
                  number: generation.respond_to?(:number) ? generation.number : nil
                ) if generation
                synchronize_catalog_for!(plugin_id, strict: true)
              end
            end
            Result.new(
              operation_id: operation_id,
              action: "enable",
              plugin_id: plugin_id,
              version: entry.manifest.version,
              status: "active",
              source: receipt["source"],
              sha256: receipt["sha256"],
              recovery_path: nil,
              data_mode: receipt["data_mode"]
            )
          end
        end

        def recover(plugin_id:, expected_version:, expected_sha256:, actor: nil,
                    dry_run: false, maintenance_mode: false)
          with_operation(
            :recover,
            plugin_id:,
            actor:,
            dry_run:,
            maintenance_mode:
          ) do |operation_id, context|
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            if active.key?(plugin_id) || disabled.key?(plugin_id)
              raise LifecycleError, "plugin #{plugin_id} is already installed"
            end

            receipt = read_receipt(plugin_id, strict: true)
            recovery = recovery_directory!(receipt.fetch("recovery_path"))
            manifest = Manifest.load_file(
              recovery.join(PackageArchive::MANIFEST_NAME)
            )
            validate_expected_id!(manifest, plugin_id)
            validate_uninstall_identity!(
              plugin_id:,
              manifest:,
              receipt:,
              expected_version:,
              expected_sha256:
            )
            validate_candidate_dependencies!(manifest, active:, disabled:)
            target = managed_path(plugin_id)
            refuse_occupied_target!(target)
            previous_plugins = runtime_plugin_versions
            bind_lifecycle_run!(
              context,
              plugin_id:,
              action: :recover,
              from_version: nil,
              to_version: manifest.version
            )
            if dry_run
              lifecycle_checkpoint!(
                context,
                "impact_analyzed",
                phase: :recover,
                to_version: manifest.version
              )
              next Result.new(
                operation_id:,
                action: "recover",
                plugin_id:,
                version: manifest.version,
                status: "validated",
                source: receipt["source"],
                sha256: receipt["sha256"],
                recovery_path: nil,
                data_mode: receipt["data_mode"]
              )
            end

            with_receipt_rollback(plugin_id) do
              move_with_runtime_rollback!(source: recovery, destination: target) do
                ensure_runtime_state!(manifest, present: true)
                lifecycle_checkpoint!(context, "runtime_verified")
                context.merge!(plugin_id:, version: manifest.version)
                write_receipt(
                  manifest:,
                  status: "active",
                  operation_id:,
                  source: receipt["source"],
                  sha256: receipt["sha256"],
                  setup_state: receipt["setup"],
                  file_manifest: receipt["file_manifest"] ||
                    FileHealth.manifest(target),
                  data_mode: receipt["data_mode"],
                  rollback_release: receipt["rollback_release"]
                )
                lifecycle_checkpoint!(context, "receipt_persisted")
                generation = coordinate_runtime_generation!(
                  action: :recover,
                  target_plugin_id: plugin_id,
                  operation_id:,
                  previous_plugins:,
                  actor: context[:actor]
                )
                lifecycle_checkpoint!(
                  context,
                  "generation_activated",
                  number: generation.respond_to?(:number) ? generation.number : nil
                ) if generation
                synchronize_catalog_for!(plugin_id, strict: true)
              end
            end

            Result.new(
              operation_id:,
              action: "recover",
              plugin_id:,
              version: manifest.version,
              status: "active",
              source: receipt["source"],
              sha256: receipt["sha256"],
              recovery_path: nil,
              data_mode: receipt["data_mode"]
            )
          end
        end

        def rollback(plugin_id:, expected_version:, expected_sha256:, actor: nil,
                     dry_run: false, maintenance_mode: false)
          with_operation(
            :rollback,
            plugin_id:,
            actor:,
            dry_run:,
            maintenance_mode:
          ) do |operation_id, context|
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            entry = active.fetch(plugin_id) do
              raise LifecycleError, "active plugin #{plugin_id} was not found"
            end
            ensure_managed_entry!(entry, managed_path(plugin_id))
            receipt = read_receipt(plugin_id, strict: true)
            validate_uninstall_identity!(
              plugin_id:,
              manifest: entry.manifest,
              receipt:,
              expected_version:,
              expected_sha256:
            )

            release = validate_rollback_release!(
              receipt["rollback_release"],
              plugin_id:
            )
            candidate = recovery_directory!(release.fetch("path"))
            manifest = Manifest.load_file(
              candidate.join(PackageArchive::MANIFEST_NAME)
            )
            validate_rollback_manifest!(manifest:, release:, plugin_id:)
            validate_rollback_files!(candidate:, release:)
            validate_candidate_dependencies!(
              manifest,
              active: active.except(plugin_id),
              disabled:
            )

            previous_plugins = runtime_plugin_versions
            current_file_manifest =
              receipt["file_manifest"] || FileHealth.manifest(entry.directory)
            bind_lifecycle_run!(
              context,
              plugin_id:,
              action: :rollback,
              from_version: entry.manifest.version,
              to_version: manifest.version
            )
            lifecycle_checkpoint!(
              context,
              "rollback_release_verified",
              version: manifest.version
            )
            if dry_run
              lifecycle_checkpoint!(
                context,
                "impact_analyzed",
                phase: :rollback,
                from_version: entry.manifest.version,
                to_version: manifest.version
              )
              next Result.new(
                operation_id:,
                action: "rollback",
                plugin_id:,
                version: manifest.version,
                status: "validated",
                source: release["source"],
                sha256: release["sha256"],
                recovery_path: nil,
                data_mode: receipt["data_mode"]
              )
            end

            with_receipt_rollback(plugin_id) do
              swap_rollback_release!(
                candidate:,
                target: entry.directory,
                current_manifest: entry.manifest
              ) do |current_backup|
                context.merge!(
                  plugin_id:,
                  version: manifest.version,
                  recovery_path: state_relative(current_backup)
                )
                ensure_runtime_state!(manifest, present: true)
                lifecycle_checkpoint!(context, "runtime_verified")
                write_receipt(
                  manifest:,
                  status: "active",
                  operation_id:,
                  source: release["source"],
                  sha256: release["sha256"],
                  recovery_path: state_relative(current_backup),
                  setup_state: receipt["setup"],
                  file_manifest: release["file_manifest"],
                  data_mode: receipt["data_mode"],
                  rollback_release: rollback_release_snapshot(
                    path: current_backup,
                    manifest: entry.manifest,
                    receipt: receipt,
                    file_manifest: current_file_manifest
                  )
                )
                lifecycle_checkpoint!(context, "receipt_persisted")
                generation = coordinate_runtime_generation!(
                  action: :rollback,
                  target_plugin_id: plugin_id,
                  operation_id:,
                  previous_plugins:,
                  actor: context[:actor]
                )
                lifecycle_checkpoint!(
                  context,
                  "generation_activated",
                  number: generation.respond_to?(:number) ? generation.number : nil
                ) if generation
                synchronize_catalog_for!(plugin_id, strict: true)
              end
            end

            Result.new(
              operation_id:,
              action: "rollback",
              plugin_id:,
              version: manifest.version,
              status: "active",
              source: release["source"],
              sha256: release["sha256"],
              recovery_path: context[:recovery_path],
              data_mode: receipt["data_mode"]
            )
          end
        end

        def uninstall(plugin_id:, expected_version:, expected_sha256:,
                      data_mode: "preserve_data", actor: nil, dry_run: false,
                      maintenance_mode: false)
          transition_to_inactive(
            plugin_id:,
            action: :uninstall,
            expected_version:,
            expected_sha256:,
            data_mode:,
            actor:,
            dry_run:,
            maintenance_mode:
          )
        end

        def health(plugin_id:)
          with_lock(shared: true) do
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            entry = active[plugin_id] || disabled[plugin_id]
            raise LifecycleError, "plugin #{plugin_id} was not found" unless entry

            receipt = read_receipt(plugin_id)
            expected = receipt["file_manifest"]
            return {
              plugin_id:,
              status: "untracked",
              expected_count: 0,
              actual_count: 0,
              missing: [],
              modified: [],
              unknown: []
            }.freeze unless expected

            FileHealth.check(directory: entry.directory, expected:).to_h.merge(plugin_id:).freeze
          end
        end

        def status(plugin_id: nil, recent_operations: 100)
          with_lock(shared: true) do
            errors = []
            active = inventory(root, errors:)
            disabled = inventory(disabled_root, errors:)
            receipts = receipt_catalog(errors:)
            runtime = runtime_catalog_for_status(errors:)
            ids = (active.keys + disabled.keys + receipts.keys).uniq.sort
            if plugin_id
              plugin_id = validate_plugin_id!(plugin_id)
              ids.select! { |id| id == plugin_id }
            end

            plugins = ids.map do |id|
              entry = active[id] || disabled[id]
              receipt = receipts.fetch(id, {})
              manifest = entry&.manifest
              filesystem_status = if active.key?(id)
                "installed"
              elsif disabled.key?(id)
                "disabled"
              else
                receipt["status"]
              end
              runtime_status = runtime[id]
              health = if entry && receipt["file_manifest"]
                FileHealth.check(directory: entry.directory, expected: receipt["file_manifest"]).to_h
              elsif entry
                { status: "untracked" }
              else
                { status: "not_installed" }
              end
              {
                id: id,
                name: manifest&.name || receipt["name"],
                version: manifest&.version || receipt["version"],
                api_version: manifest&.api_version || receipt["api_version"],
                status: active.key?(id) ? runtime_status || "not_loaded" : filesystem_status,
                filesystem_status: filesystem_status,
                runtime_status: runtime_status,
                source: receipt["source"],
                sha256: receipt["sha256"],
                recovery_path: receipt["recovery_path"],
                updated_at: receipt["updated_at"],
                last_operation_id: receipt["last_operation_id"],
                setup: receipt["setup"],
                data_mode: receipt["data_mode"],
                rollback_available: rollback_release_available?(
                  receipt["rollback_release"]
                ),
                health: health
              }.compact.freeze
            end.freeze

            {
              plugins: plugins,
              errors: errors.freeze,
              operations: @journal.recent(limit: recent_operations)
            }.freeze
          end
        end

        # Rebuilds the database catalog from the authoritative manifest,
        # receipt, runtime, and managed-file views. It never changes plugin
        # packages, receipts, runtime registrations, or recovery files.
        def reconcile_catalog
          with_lock do
            unless @catalog_store&.available?
              raise LifecycleError, "plugin catalog database is unavailable"
            end

            errors = []
            active = inventory(root, errors:)
            disabled = inventory(disabled_root, errors:)
            receipts = receipt_catalog(errors:)
            runtime = runtime_catalog_for_status(errors:)
            known_catalog_ids = @catalog_store.plugin_ids
            ids = (
              active.keys + disabled.keys + receipts.keys + known_catalog_ids
            ).uniq.sort
            findings = errors.map do |error|
              catalog_finding(
                plugin_id: nil,
                code: error.fetch(:code, "catalog_scan_failed"),
                severity: "error"
              )
            end
            synchronized_count = 0
            unavailable_count = 0

            ids.each do |id|
              plugin_findings = []
              entry = active[id] || disabled[id]
              receipt = receipts.fetch(id, {})
              state = catalog_state(
                active: active.key?(id),
                disabled: disabled.key?(id),
                receipt:
              )
              if active.key?(id) && disabled.key?(id)
                plugin_findings << catalog_finding(
                  plugin_id: id,
                  code: "filesystem_status_mismatch",
                  severity: "error"
                )
              end
              if receipt.empty?
                plugin_findings << catalog_finding(
                  plugin_id: id,
                  code: "receipt_missing",
                  severity: "warning"
                )
              elsif receipt["status"].to_s != state
                plugin_findings << catalog_finding(
                  plugin_id: id,
                  code: "receipt_status_mismatch",
                  severity: "error"
                )
              end
              unless known_catalog_ids.include?(id)
                plugin_findings << catalog_finding(
                  plugin_id: id,
                  code: "catalog_record_missing",
                  severity: "warning"
                )
              end
              plugin_findings.concat(
                runtime_catalog_findings(
                  plugin_id: id,
                  state:,
                  runtime_status: runtime[id]
                )
              )

              directory = entry&.directory
              manifest = entry&.manifest
              if !manifest && state == "uninstalled"
                begin
                  directory = recovery_directory!(receipt["recovery_path"])
                  manifest = Manifest.load_file(
                    directory.join(PackageArchive::MANIFEST_NAME)
                  )
                rescue StandardError
                  plugin_findings << catalog_finding(
                    plugin_id: id,
                    code: "filesystem_missing",
                    severity: "error"
                  )
                end
              elsif !manifest
                plugin_findings << catalog_finding(
                  plugin_id: id,
                  code: "filesystem_missing",
                  severity: "error"
                )
              end

              if manifest
                if receipt.present? && !receipt["file_manifest"].is_a?(Hash)
                  plugin_findings << catalog_finding(
                    plugin_id: id,
                    code: "file_manifest_invalid",
                    severity: "warning"
                  )
                elsif receipt["file_manifest"].is_a?(Hash)
                  health = FileHealth.check(
                    directory:,
                    expected: receipt["file_manifest"]
                  )
                  unless health.healthy?
                    plugin_findings << catalog_finding(
                      plugin_id: id,
                      code: "file_health_changed",
                      severity: "error"
                    )
                  end
                end

                @catalog_store.synchronize!(
                  plugin_id: id,
                  state:,
                  manifest:,
                  package_sha256: receipt["sha256"],
                  expected_file_manifest: receipt["file_manifest"],
                  directory:,
                  operation_id: receipt["last_operation_id"],
                  diagnostics: plugin_findings,
                  rollback_release: catalog_rollback_release(
                    receipt["rollback_release"],
                    strict: false
                  )
                )
                synchronized_count += 1
              else
                @catalog_store.mark_unavailable!(
                  plugin_id: id,
                  state:,
                  diagnostics: plugin_findings
                )
                unavailable_count += 1
              end
              findings.concat(plugin_findings)
            rescue StandardError
              unavailable_count += 1
              failure = catalog_finding(
                plugin_id: id,
                code: "contribution_catalog_invalid",
                severity: "error"
              )
              findings << failure
              @catalog_store.mark_unavailable!(
                plugin_id: id,
                state: state || "uninstalled",
                diagnostics: plugin_findings.to_a + [ failure ]
              )
            end

            (runtime.keys - ids).sort.each do |id|
              findings << catalog_finding(
                plugin_id: id,
                code: "runtime_without_filesystem",
                severity: "error"
              )
            end
            findings = findings.uniq.freeze
            ReconcileResult.new(
              scanned_count: ids.length,
              synchronized_count:,
              unavailable_count:,
              finding_count: findings.length,
              findings:
            )
          end
        end

        private

        def transition_to_inactive(plugin_id:, action:, expected_version: nil, expected_sha256: nil,
                                   data_mode: "preserve_data", actor: nil,
                                   dry_run: false, maintenance_mode: false)
          with_operation(
            action,
            plugin_id:,
            actor:,
            dry_run:,
            maintenance_mode:
          ) do |operation_id, context|
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            previous_plugins = runtime_plugin_versions
            entry = active[plugin_id] || disabled[plugin_id]
            raise LifecycleError, "plugin #{plugin_id} was not found" unless entry
            raise LifecycleError, "plugin #{plugin_id} is already disabled" if action == :disable && disabled.key?(plugin_id)

            expected_directory = active.key?(plugin_id) ? managed_path(plugin_id) : disabled_path(plugin_id)
            ensure_managed_entry!(entry, expected_directory)
            receipt = read_receipt(
              plugin_id,
              strict: action == :uninstall || entry.manifest.setup.present?
            )
            context.merge!(
              plugin_id: plugin_id,
              version: entry.manifest.version,
              sha256: receipt["sha256"]
            )
            if action == :uninstall
              data_mode = validate_uninstall_data_mode!(data_mode)
              validate_uninstall_identity!(
                plugin_id:,
                manifest: entry.manifest,
                receipt:,
                expected_version:,
                expected_sha256:
              )
            end
            validate_no_dependants!(plugin_id, active.merge(disabled))
            destination = if action == :disable
              disabled_path(plugin_id)
            else
              quarantined_path(operation_id, plugin_id)
            end
            raise LifecycleError, "plugin lifecycle destination already exists" if destination.exist?

            result_status = action == :disable ? "disabled" : "uninstalled"
            setup_plan = load_setup_plan(entry.directory, entry.manifest) if action == :uninstall &&
              data_mode == "purge_data"
            initial_setup_state = Setup::State.load(receipt["setup"]) if setup_plan
            bind_lifecycle_run!(
              context,
              plugin_id:,
              action:,
              from_version: entry.manifest.version,
              to_version: nil
            )
            if dry_run
              lifecycle_checkpoint!(
                context,
                "impact_analyzed",
                phase: action,
                from_version: entry.manifest.version,
                data_mode: action == :uninstall ? data_mode : nil,
                setup_step_count: setup_plan&.steps&.length || 0
              )
              next lifecycle_preview_result(
                operation_id:,
                action:,
                entry:,
                receipt:,
                data_mode: action == :uninstall ? data_mode : receipt["data_mode"]
              )
            end

            with_receipt_rollback(plugin_id) do
              move_with_runtime_rollback!(source: entry.directory, destination: destination) do
                recovery_path = state_relative(destination)
                context.merge!(
                  plugin_id: plugin_id,
                  version: entry.manifest.version,
                  recovery_path: recovery_path
                )
                with_setup_transaction(
                  plan: setup_plan,
                  phase: :uninstall,
                  state: initial_setup_state,
                  plugin_id: plugin_id,
                  from_version: entry.manifest.version,
                  to_version: nil,
                  operation_id:
                ) do |completed_setup_state|
                  lifecycle_checkpoint!(context, "setup_committed") if setup_plan
                  ensure_runtime_state!(entry.manifest, present: false)
                  lifecycle_checkpoint!(context, "runtime_verified")
                  write_receipt(
                    manifest: entry.manifest,
                    status: result_status,
                    operation_id: operation_id,
                    source: receipt["source"],
                    sha256: receipt["sha256"],
                    recovery_path: recovery_path,
                    setup_state: completed_setup_state&.to_h || receipt["setup"],
                    file_manifest: receipt["file_manifest"],
                    data_mode: action == :uninstall ? data_mode : receipt["data_mode"],
                    rollback_release: receipt["rollback_release"]
                  )
                  lifecycle_checkpoint!(context, "receipt_persisted")
                  generation = coordinate_runtime_generation!(
                    action:,
                    target_plugin_id: plugin_id,
                    operation_id:,
                    previous_plugins:,
                    actor: context[:actor]
                  )
                  lifecycle_checkpoint!(
                    context,
                    "generation_activated",
                    number: generation.respond_to?(:number) ? generation.number : nil
                  ) if generation
                  purge_owned_host_data!(plugin_id) if
                    action == :uninstall && data_mode == "purge_data"
                  lifecycle_checkpoint!(context, "host_data_purged") if
                    action == :uninstall && data_mode == "purge_data"
                  synchronize_catalog_for!(plugin_id, strict: true)
                end
              end
            end
            recovery_path = state_relative(destination)
            Result.new(
              operation_id: operation_id,
              action: action.to_s,
              plugin_id: plugin_id,
              version: entry.manifest.version,
              status: result_status,
              source: receipt["source"],
              sha256: receipt["sha256"],
              recovery_path: recovery_path,
              data_mode: action == :uninstall ? data_mode : receipt["data_mode"]
            )
          end
        end

        def with_operation(action, plugin_id: nil, actor: nil, dry_run: false,
                           maintenance_mode: false)
          with_lock do
            maintenance_window = nil
            operation_id = @journal.start(action:, plugin_id:)
            context = { plugin_id: plugin_id, actor: actor }
            lifecycle_run = @lifecycle_store&.start!(
              operation_id:,
              action:,
              plugin_id:,
              actor:,
              dry_run:,
              maintenance_mode:
            )
            if maintenance_mode && !dry_run
              maintenance_window = @lifecycle_store&.open_maintenance!(
                operation_id:,
                plugin_id:,
                actor:
              )
            end
            context.merge!(
              lifecycle_run:,
              dry_run:,
              maintenance_mode:
            )
            result = yield(operation_id, context)
            finish_journal(
              operation_id: operation_id,
              action: result.action,
              status: "succeeded",
              plugin_id: result.plugin_id,
              version: result.version,
              source: result.source,
              sha256: result.sha256,
              recovery_path: result.recovery_path
            )
            @lifecycle_store&.finish!(
              run: lifecycle_run,
              succeeded: true,
              plugin_id: result.plugin_id,
              version: result.version,
              recovery_path: result.recovery_path
            )
            result
          rescue StandardError => e
            finish_journal(
              operation_id: operation_id,
              action: action,
              status: "failed",
              plugin_id: context&.fetch(:plugin_id, nil),
              version: context&.fetch(:version, nil),
              source: context&.fetch(:source, nil),
              sha256: context&.fetch(:sha256, nil),
              message: e.message,
              error_class: e.class.name,
              recovery_path: context&.fetch(:recovery_path, nil)
            ) if operation_id
            @lifecycle_store&.finish!(
              run: lifecycle_run,
              succeeded: false,
              plugin_id: context&.fetch(:plugin_id, nil),
              version: context&.fetch(:version, nil),
              recovery_path: context&.fetch(:recovery_path, nil),
              error: e
            ) if lifecycle_run
            raise
          ensure
            @lifecycle_store&.close_maintenance!(maintenance_window) if
              maintenance_window
          end
        end

        def default_lifecycle_store
          return unless @root == Mcweb::Plugins.default_root.expand_path.cleanpath

          store = LifecycleStore.new(clock: @clock)
          store if store.available?
        rescue StandardError
          nil
        end

        def default_catalog_store
          return unless @root == Mcweb::Plugins.default_root.expand_path.cleanpath

          store = CatalogStore.new(clock: @clock)
          store if store.available?
        rescue StandardError
          nil
        end

        def synchronize_catalog_for!(plugin_id, strict:)
          return unless @catalog_store

          active = active_inventory!
          disabled = disabled_inventory!
          receipt = read_receipt(plugin_id, strict:)
          entry = active[plugin_id] || disabled[plugin_id]
          state = catalog_state(
            active: active.key?(plugin_id),
            disabled: disabled.key?(plugin_id),
            receipt:
          )
          directory = entry&.directory
          manifest = entry&.manifest
          if !manifest && state == "uninstalled"
            directory = recovery_directory!(receipt.fetch("recovery_path"))
            manifest = Manifest.load_file(
              directory.join(PackageArchive::MANIFEST_NAME)
            )
          end
          raise LifecycleError, "plugin catalog manifest is unavailable" unless manifest

          @catalog_store.synchronize!(
            plugin_id:,
            state:,
            manifest:,
            package_sha256: receipt["sha256"],
            expected_file_manifest: receipt["file_manifest"],
            directory:,
            operation_id: receipt["last_operation_id"],
            rollback_release: catalog_rollback_release(
              receipt["rollback_release"],
              strict:
            )
          )
        rescue StandardError
          raise if strict

          nil
        end

        def catalog_rollback_release(value, strict:)
          return unless value.is_a?(Hash)

          directory = recovery_directory!(value.fetch("path"))
          manifest = Manifest.load_file(
            directory.join(PackageArchive::MANIFEST_NAME)
          )
          {
            manifest:,
            package_sha256: value["sha256"],
            expected_file_manifest: value["file_manifest"],
            directory:
          }.freeze
        rescue StandardError
          raise if strict

          nil
        end

        def catalog_state(active:, disabled:, receipt:)
          return "active" if active
          return "disabled" if disabled
          return "uninstalled" if receipt["status"].to_s == "uninstalled"

          status = receipt["status"].to_s
          %w[active disabled].include?(status) ? status : "uninstalled"
        end

        def runtime_catalog_findings(plugin_id:, state:, runtime_status:)
          if state == "active"
            return [] if ACTIVE_RUNTIME_STATUSES.include?(runtime_status.to_s)

            code = runtime_status.present? ?
              "runtime_status_mismatch" : "runtime_missing"
            return [
              catalog_finding(plugin_id:, code:, severity: "error")
            ]
          end
          return [] if runtime_status.blank?

          [
            catalog_finding(
              plugin_id:,
              code: "runtime_status_mismatch",
              severity: "error"
            )
          ]
        end

        def catalog_finding(plugin_id:, code:, severity:)
          {
            plugin_id: plugin_id.to_s.presence,
            code: code.to_s.slice(0, 128),
            severity: severity.to_s.in?(%w[warning error]) ?
              severity.to_s : "warning"
          }.compact.freeze
        end

        def bind_lifecycle_run!(context, plugin_id:, action: nil,
                                from_version: nil, to_version: nil)
          context[:plugin_id] = plugin_id
          return unless context[:lifecycle_run]

          @lifecycle_store.bind!(
            run: context[:lifecycle_run],
            plugin_id:,
            action:,
            from_version:,
            to_version:
          )
        end

        def lifecycle_checkpoint!(context, step_key, details = {})
          return unless context[:lifecycle_run]

          @lifecycle_store.checkpoint!(
            run: context[:lifecycle_run],
            step_key:,
            details:
          )
        end

        def default_generation_coordinator
          return unless @root == Mcweb::Plugins.default_root.expand_path.cleanpath

          coordinator = Mcweb::Plugins.generation_coordinator
          coordinator if coordinator.available?
        rescue StandardError
          nil
        end

        def coordinate_runtime_generation!(action:, target_plugin_id:, operation_id:,
                                           previous_plugins:, actor: nil)
          return unless @generation_coordinator

          @generation_coordinator.publish!(
            desired_plugins: runtime_plugin_versions,
            previous_plugins:,
            action: action.to_s,
            target_plugin_id:,
            operation_id:,
            actor:,
            timeout: ENV.fetch("MCWEB_PLUGIN_GENERATION_TIMEOUT_SECONDS", "45").to_i.seconds,
            minimum_ack_ratio: ENV.fetch("MCWEB_PLUGIN_GENERATION_ACK_RATIO", "1"),
            wait_for_acknowledgements: true
          )
        end

        def purge_owned_host_data!(plugin_id)
          Mcweb::Plugins::OwnedDataPurger.call(plugin_id:)
        end

        def runtime_plugin_versions
          Array(@runtime_catalog.call).filter_map do |entry|
            status = runtime_value(entry, :status).to_s
            next unless ACTIVE_RUNTIME_STATUSES.include?(status)

            id = runtime_value(entry, :id).to_s
            version = runtime_value(entry, :version).to_s
            [ id, version ] if id.present? && version.present?
          end.to_h.sort.to_h.freeze
        rescue StandardError
          {}.freeze
        end

        def finish_journal(**attributes)
          @journal.finish(**attributes)
        rescue StandardError => e
          logger&.error("[mcweb.plugin_marketplace] unable to finish operation journal: #{e.class}: #{e.message}")
          nil
        end

        def lifecycle_preview_result(operation_id:, action:, entry:, receipt:,
                                     data_mode: nil)
          Result.new(
            operation_id:,
            action: action.to_s,
            plugin_id: entry.manifest.id,
            version: entry.manifest.version,
            status: "validated",
            source: receipt["source"],
            sha256: receipt["sha256"],
            recovery_path: nil,
            data_mode:
          )
        end

        def with_lock(shared: false)
          prepare_roots!
          File.open(state_root.join("marketplace.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
            lock.flock(shared ? File::LOCK_SH : File::LOCK_EX)
            yield
          ensure
            lock.flock(File::LOCK_UN)
          end
        end

        def prepare_roots!
          root.mkpath(mode: 0o755)
          state_root.mkpath(mode: 0o700)
          if contained_path?(state_root.realpath, root.realpath)
            raise LifecycleError, "marketplace state directory must remain outside the plugin root"
          end
          return if File.stat(root).dev == File.stat(state_root).dev

          raise LifecycleError, "plugin root and marketplace state must share a filesystem for atomic operations"
        end

        def activate_candidate!(stage:, target:, manifest:)
          backup = nil
          if target.exist?
            backup = backup_path(manifest.id, manifest.version)
            backup.dirname.mkpath(mode: 0o700)
            File.rename(target, backup)
          else
            target.dirname.mkpath(mode: 0o755)
          end

          begin
            File.rename(stage, target)
            yield backup if block_given?
          rescue StandardError => original_error
            failed = failed_path(manifest.id)
            failed.dirname.mkpath(mode: 0o700)
            File.rename(target, failed) if target.exist?
            File.rename(backup, target) if backup&.exist?
            rollback_error = reload_after_rollback
            message = "plugin activation failed; previous filesystem state restored: #{original_error.message}"
            message += " (runtime rollback also failed: #{rollback_error.message})" if rollback_error
            raise LifecycleError, message
          end
          backup
        end

        def swap_rollback_release!(candidate:, target:, current_manifest:)
          backup = backup_path(current_manifest.id, current_manifest.version)
          backup.dirname.mkpath(mode: 0o700)
          File.rename(target, backup)

          begin
            File.rename(candidate, target)
            yield backup
          rescue StandardError => original_error
            candidate.dirname.mkpath(mode: 0o700)
            File.rename(target, candidate) if target.exist? && !candidate.exist?
            File.rename(backup, target) if backup.exist? && !target.exist?
            rollback_error = reload_after_rollback
            message =
              "plugin rollback failed; current release and rollback point were restored: " \
              "#{original_error.message}"
            if rollback_error
              message +=
                " (runtime rollback also failed: #{rollback_error.message})"
            end
            raise LifecycleError, message
          end
          backup
        end

        def move_with_runtime_rollback!(source:, destination:)
          destination.dirname.mkpath(mode: 0o700)
          File.rename(source, destination)
          yield if block_given?
        rescue StandardError => original_error
          File.rename(destination, source) if destination.exist? && !source.exist?
          rollback_error = reload_after_rollback
          message = "plugin lifecycle change failed; filesystem state restored: #{original_error.message}"
          message += " (runtime rollback also failed: #{rollback_error.message})" if rollback_error
          raise LifecycleError, message
        end

        def ensure_runtime_state!(manifest, present:)
          catalog = Array(@reload_callback.call || @runtime_catalog.call)
          runtime = catalog.find { |entry| runtime_value(entry, :id) == manifest.id }
          if present
            status = runtime_value(runtime, :status)
            return if runtime && ACTIVE_RUNTIME_STATUSES.include?(status)

            raise LifecycleError, "plugin #{manifest.id} did not become active after reload"
          end
          raise LifecycleError, "plugin #{manifest.id} remained in the runtime catalog after reload" if runtime

          true
        end

        def reload_after_rollback
          @reload_callback.call
          nil
        rescue StandardError => e
          e
        end

        def runtime_value(entry, key)
          return unless entry

          hash = entry.respond_to?(:to_h) ? entry.to_h : {}
          (hash[key] || hash[key.to_s]).to_s
        end

        def validate_expected_id!(manifest, expected_id)
          return if expected_id.nil?

          expected_id = validate_plugin_id!(expected_id)
          return if manifest.id == expected_id

          raise PackageError, "plugin package id does not match the requested plugin"
        end

        def validate_install_target!(manifest, active:, disabled:)
          raise LifecycleError, "plugin #{manifest.id} is disabled; enable it before upgrading" if disabled.key?(manifest.id)

          target = managed_path(manifest.id)
          installed = active[manifest.id]
          if installed && installed.directory != target
            raise LifecycleError, "plugin #{manifest.id} is not installed in its managed marketplace path"
          end
          refuse_occupied_target!(target) unless installed
        end

        def refuse_occupied_target!(target)
          ensure_no_symlink_components!(target)
          return unless target.exist? || target.symlink?

          raise LifecycleError, "managed plugin path is occupied by unrelated files"
        end

        def ensure_managed_entry!(entry, expected_directory)
          return if entry.directory == expected_directory

          raise LifecycleError, "plugin is outside its managed marketplace path"
        end

        def validate_version_change!(candidate, installed, allow_downgrade:)
          return unless installed

          current = installed.manifest
          comparison = candidate.version_object <=> current.version_object
          if comparison.zero?
            raise CompatibilityError, "plugin #{candidate.id} #{candidate.version} is already installed"
          end
          if comparison.negative? && !allow_downgrade
            raise CompatibilityError, "plugin downgrade requires allow_downgrade: true"
          end
        end

        def validate_candidate_dependencies!(candidate, active:, disabled:)
          proposed = active.transform_values(&:manifest).merge(candidate.id => candidate)
          runtime = Array(@runtime_catalog.call)
          candidate.requires.each do |dependency_id, requirement|
            dependency = proposed[dependency_id]
            if dependency.nil? && disabled.key?(dependency_id)
              raise DependencyError, "dependency #{dependency_id} is disabled"
            end
            raise DependencyError, "missing dependency #{dependency_id}" unless dependency
            unless Gem::Requirement.new(requirement).satisfied_by?(dependency.version_object)
              raise DependencyError, "dependency #{dependency_id} #{dependency.version} does not satisfy #{requirement}"
            end

            runtime_entry = runtime.find { |entry| runtime_value(entry, :id) == dependency_id }
            unless ACTIVE_RUNTIME_STATUSES.include?(runtime_value(runtime_entry, :status))
              raise DependencyError, "dependency #{dependency_id} is not active in this process"
            end
          end

          active.merge(disabled).each_value do |entry|
            requirement = entry.manifest.requires[candidate.id]
            next unless requirement
            next if Gem::Requirement.new(requirement).satisfied_by?(candidate.version_object)

            raise DependencyError, "#{entry.manifest.id} requires #{candidate.id} #{requirement}"
          end
          validate_no_candidate_cycle!(candidate.id, proposed)
        end

        def validate_no_candidate_cycle!(candidate_id, manifests)
          visiting = []
          visited = {}
          visit = lambda do |plugin_id|
            return if visited[plugin_id]
            if visiting.include?(plugin_id)
              cycle = visiting.drop_while { |id| id != plugin_id } + [ plugin_id ]
              raise DependencyError, "dependency cycle: #{cycle.join(' -> ')}"
            end

            visiting << plugin_id
            manifests.fetch(plugin_id).requires.each_key do |dependency_id|
              visit.call(dependency_id) if manifests.key?(dependency_id)
            end
            visiting.pop
            visited[plugin_id] = true
          end
          visit.call(candidate_id)
        end

        def validate_no_dependants!(plugin_id, inventory)
          dependants = inventory.values.select { |entry| entry.manifest.requires.key?(plugin_id) }
          return if dependants.empty?

          ids = dependants.map { |entry| entry.manifest.id }.sort
          raise DependencyError, "plugin #{plugin_id} is required by #{ids.join(', ')}"
        end

        def active_inventory!
          inventory(root)
        end

        def disabled_inventory!
          inventory(disabled_root)
        end

        def inventory(base, errors: nil)
          return {} unless base.directory?

          entries = {}
          Find.find(base.realpath.to_s) do |path|
            candidate = Pathname(path)
            if candidate != base.realpath && candidate.symlink? && candidate.directory?
              Find.prune
            end
            next unless candidate.basename.to_s == PackageArchive::MANIFEST_NAME

            real_path = candidate.realpath
            next unless contained_path?(real_path, base.realpath)

            manifest = Manifest.load_file(real_path)
            if entries.key?(manifest.id)
              raise LifecycleError, "duplicate installed plugin id #{manifest.id}"
            end
            entries[manifest.id] = InventoryEntry.new(
              manifest: manifest,
              directory: real_path.dirname,
              manifest_path: real_path
            )
          rescue StandardError => e
            raise unless errors

            errors << {
              code: "invalid_installed_plugin",
              path: safe_relative(candidate, base),
              message: e.message.to_s.slice(0, 1_024)
            }.freeze
          end
          entries.freeze
        rescue SystemCallError, ArgumentError => e
          raise LifecycleError, "unable to scan plugin inventory: #{e.message}" unless errors

          errors << { code: "plugin_inventory_scan_failed", message: e.message.to_s.slice(0, 1_024) }.freeze
          {}.freeze
        end

        def load_package_metadata(stage)
          path = stage.join(PackageMetadata::FILE_NAME)
          PackageMetadata.load_file(path) if path.file?
        end

        def load_setup_plan(directory, manifest)
          return unless manifest.setup

          setup_path = resolve_package_file(directory, manifest.setup)
          Setup.load_file(
            setup_path,
            plugin_id: manifest.id,
            package_version: manifest.version
          )
        end

        def resolve_package_file(directory, relative_path)
          root_real = Pathname(directory).realpath
          candidate = root_real.join(relative_path).cleanpath
          candidate_real = candidate.realpath
          unless candidate_real.file? && contained_path?(candidate_real, root_real)
            raise SetupError, "plugin setup file must remain inside the plugin package"
          end

          candidate_real
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, ArgumentError
          raise SetupError, "plugin setup file is unavailable"
        end

        def with_setup_transaction(plan:, phase:, state:, plugin_id:, from_version:, to_version:, operation_id:)
          return yield(nil) unless plan
          unless defined?(ActiveRecord::Base)
            raise SetupError, "plugin setup database lifecycle is unavailable"
          end

          completed_state = nil
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.transaction(requires_new: true) do
              completed_state = Setup.execute(
                plan:,
                phase:,
                state:,
                plugin_id:,
                from_version:,
                to_version:,
                operation_id:,
                connection:,
                clock: @clock
              )
            end
          end
          # Runtime generations must be published only after setup commits.
          # Otherwise other web/worker processes cannot observe the generation
          # row while this process waits for their acknowledgements.
          yield completed_state
        end

        def managed_path(plugin_id)
          plugin_id = validate_plugin_id!(plugin_id)
          root.join(*plugin_id.split("/")).tap { |path| ensure_no_symlink_components!(path) }
        end

        def recovery_directory!(relative_path)
          value = relative_path.to_s
          raise LifecycleError, "plugin recovery files are unavailable" if value.blank?

          candidate = state_root.join(value).cleanpath
          unless contained_path?(candidate, state_root) && candidate.directory?
            raise LifecycleError, "plugin recovery files are unavailable"
          end
          ensure_no_symlink_components!(candidate, base: state_root)
          candidate
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, ArgumentError
          raise LifecycleError, "plugin recovery files are unavailable"
        end

        def validate_rollback_release!(release, plugin_id:)
          unless release.is_a?(Hash) &&
              release["path"].present? &&
              release["id"] == plugin_id &&
              release["version"].present? &&
              release["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
              release["file_manifest"].is_a?(Hash)
            raise LifecycleError, "verified plugin rollback release is unavailable"
          end

          release
        end

        def validate_rollback_manifest!(manifest:, release:, plugin_id:)
          unless manifest.id == plugin_id &&
              manifest.id == release["id"] &&
              manifest.version == release["version"] &&
              manifest.api_version == release["api_version"]
            raise IntegrityError,
              "plugin rollback release identity changed or cannot be verified"
          end
        end

        def validate_rollback_files!(candidate:, release:)
          health = FileHealth.check(
            directory: candidate,
            expected: release.fetch("file_manifest")
          )
          return if health.healthy?

          raise IntegrityError,
            "plugin rollback release files changed or cannot be verified"
        end

        def rollback_release_available?(release)
          return false unless release.is_a?(Hash)

          candidate = recovery_directory!(release["path"])
          manifest = Manifest.load_file(
            candidate.join(PackageArchive::MANIFEST_NAME)
          )
          validate_rollback_manifest!(
            manifest:,
            release:,
            plugin_id: release["id"].to_s
          )
          validate_rollback_files!(candidate:, release:)
          true
        rescue StandardError
          false
        end

        def disabled_path(plugin_id)
          plugin_id = validate_plugin_id!(plugin_id)
          disabled_root.join(*plugin_id.split("/")).tap { |path| ensure_no_symlink_components!(path, base: state_root) }
        end

        def disabled_root
          state_root.join("disabled")
        end

        def staging_path(operation_id)
          state_root.join("staging", operation_id)
        end

        def backup_path(plugin_id, new_version)
          state_root.join("backups", "#{timestamp_slug}-#{new_version}-#{SecureRandom.hex(6)}", *plugin_id.split("/"))
        end

        def failed_path(plugin_id)
          state_root.join("failed", "#{timestamp_slug}-#{SecureRandom.hex(6)}", *plugin_id.split("/"))
        end

        def quarantined_path(operation_id, plugin_id)
          state_root.join("quarantine", "#{timestamp_slug}-#{operation_id}", *plugin_id.split("/"))
        end

        def validate_plugin_id!(plugin_id)
          plugin_id = plugin_id.to_s
          unless plugin_id.length <= Manifest::MAX_ID_LENGTH && plugin_id.match?(Manifest::ID_PATTERN)
            raise LifecycleError, "invalid plugin id"
          end
          if plugin_id.split("/").any? { |part| PackageArchive::WINDOWS_RESERVED_NAMES.include?(part.split(".", 2).first) }
            raise LifecycleError, "plugin id is not portable"
          end

          plugin_id
        end

        def validate_uninstall_identity!(plugin_id:, manifest:, receipt:, expected_version:, expected_sha256:)
          expected_version = expected_version.to_s
          expected_sha256 = expected_sha256.to_s.downcase
          actual_sha256 = receipt["sha256"].to_s.downcase
          expected_identity_valid =
            expected_version.length <= Manifest::MAX_VERSION_LENGTH &&
            expected_version.match?(Manifest::SEMVER_PATTERN) &&
            expected_sha256.match?(PackageArchive::SHA256_PATTERN)
          receipt_identity_valid =
            receipt["id"].to_s == plugin_id &&
            receipt["version"].to_s == manifest.version &&
            actual_sha256.match?(PackageArchive::SHA256_PATTERN)

          unless expected_identity_valid &&
                 receipt_identity_valid &&
                 expected_version == manifest.version &&
                 expected_sha256 == actual_sha256
            raise IntegrityError, UNINSTALL_IDENTITY_ERROR
          end
        end

        def validate_uninstall_data_mode!(value)
          mode = value.to_s
          return mode if UNINSTALL_DATA_MODES.include?(mode)

          raise LifecycleError,
            "uninstall data mode must be one of: #{UNINSTALL_DATA_MODES.join(', ')}"
        end

        def rollback_release_snapshot(path:, manifest:, receipt:, file_manifest: nil)
          {
            "path" => state_relative(path),
            "id" => manifest.id,
            "version" => manifest.version,
            "api_version" => manifest.api_version,
            "source" => receipt["source"],
            "sha256" => receipt["sha256"],
            "file_manifest" => file_manifest || receipt["file_manifest"] ||
              FileHealth.manifest(path)
          }.compact.freeze
        end

        def write_receipt(manifest:, status:, operation_id:, source: nil, sha256: nil,
                          recovery_path: nil, setup_state: nil, file_manifest: nil,
                          data_mode: nil, rollback_release: nil)
          path = receipt_path(manifest.id)
          path.dirname.mkpath(mode: 0o700)
          payload = {
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            api_version: manifest.api_version,
            status: status,
            source: source,
            sha256: sha256,
            recovery_path: recovery_path,
            setup: setup_state,
            file_manifest: file_manifest,
            data_mode: data_mode,
            rollback_release: rollback_release,
            updated_at: @clock.call.utc.iso8601(6),
            last_operation_id: operation_id
          }.compact
          temporary = path.dirname.join(".#{path.basename}.#{SecureRandom.hex(6)}.tmp")
          created_temporary = false
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            created_temporary = true
            file.write(JSON.generate(payload))
            file.flush
            file.fsync
          end
          File.rename(temporary, path)
          payload.freeze
        ensure
          FileUtils.rm_f(temporary) if created_temporary && temporary&.exist?
        end

        def read_receipt(plugin_id, strict: false)
          path = receipt_path(plugin_id)
          return {} unless path.file?

          JSON.parse(path.read)
        rescue JSON::ParserError, Errno::ENOENT
          raise LifecycleError, "marketplace receipt is invalid" if strict

          {}
        end

        def receipt_catalog(errors:)
          return {} unless receipts_root.directory?

          receipts_root.glob("**/*.json").each_with_object({}) do |path, catalog|
            data = JSON.parse(path.read)
            plugin_id = validate_plugin_id!(data.fetch("id"))
            catalog[plugin_id] = data.freeze
          rescue StandardError => e
            errors << {
              code: "invalid_marketplace_receipt",
              path: safe_relative(path, receipts_root),
              message: e.message.to_s.slice(0, 1_024)
            }.freeze
          end.freeze
        end

        def runtime_catalog_for_status(errors:)
          Array(@runtime_catalog.call).each_with_object({}) do |entry, catalog|
            plugin_id = runtime_value(entry, :id)
            next if plugin_id.empty?

            catalog[plugin_id] = runtime_value(entry, :status)
          end.freeze
        rescue StandardError => e
          errors << {
            code: "plugin_runtime_catalog_failed",
            message: e.message.to_s.slice(0, 1_024)
          }.freeze
          {}.freeze
        end

        def receipt_path(plugin_id)
          receipts_root.join(*validate_plugin_id!(plugin_id).split("/")).sub_ext(".json").tap do |path|
            ensure_no_symlink_components!(path, base: state_root)
          end
        end

        def receipts_root
          state_root.join("receipts")
        end

        def with_receipt_rollback(plugin_id)
          path = receipt_path(plugin_id)
          existed = path.exist?
          previous = path.binread if path.file?
          yield
        rescue StandardError => original_error
          begin
            if previous
              path.dirname.mkpath(mode: 0o700)
              temporary = path.dirname.join(".#{path.basename}.rollback-#{SecureRandom.hex(6)}.tmp")
              File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
                file.write(previous)
                file.flush
                file.fsync
              end
              File.rename(temporary, path)
            elsif !existed && path&.file?
              FileUtils.rm_f(path)
            end
          rescue StandardError => rollback_error
            raise LifecycleError,
                  "plugin lifecycle receipt rollback failed (#{rollback_error.class.name})"
          ensure
            FileUtils.rm_f(temporary) if temporary&.exist?
          end
          raise original_error
        end

        def state_relative(path)
          path.relative_path_from(state_root).to_s.tr("\\", "/")
        end

        def safe_relative(path, base)
          Pathname(path).relative_path_from(Pathname(base)).to_s.tr("\\", "/")
        rescue ArgumentError
          Pathname(path).basename.to_s
        end

        def timestamp_slug
          @clock.call.utc.strftime("%Y%m%d%H%M%S")
        end

        def contained_path?(candidate, base)
          relative = Pathname(candidate).cleanpath.relative_path_from(Pathname(base).cleanpath)
          !relative.absolute? && relative.each_filename.first != ".."
        rescue ArgumentError
          false
        end

        def ensure_no_symlink_components!(target, base: root)
          relative = Pathname(target).cleanpath.relative_path_from(Pathname(base).cleanpath)
          if relative.absolute? || relative.each_filename.first == ".."
            raise LifecycleError, "managed plugin path escapes its configured root"
          end

          current = Pathname(base)
          relative.each_filename do |component|
            current = current.join(component)
            if current.symlink?
              raise LifecycleError, "managed plugin path contains a symbolic link"
            end
          end
          true
        rescue ArgumentError
          raise LifecycleError, "managed plugin path escapes its configured root"
        end

        def default_state_root
          if defined?(Rails) && Rails.respond_to?(:root)
            Rails.root.join("storage", "plugin_marketplace")
          else
            root.dirname.join("plugin_marketplace_state")
          end
        end

        def logger
          Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
        end
      end
    end
  end
end
