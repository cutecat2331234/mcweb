# frozen_string_literal: true

require "fileutils"
require "find"
require "json"
require "pathname"
require "securerandom"
require "time"
require_relative "../manifest"
require_relative "error"
require_relative "operation_journal"
require_relative "package_archive"
require_relative "package_metadata"
require_relative "setup"

module Mcweb
  module Plugins
    module Marketplace
      class Manager
        ACTIVE_RUNTIME_STATUSES = %w[active degraded].freeze
        Result = Data.define(
          :operation_id, :action, :plugin_id, :version, :status,
          :source, :sha256, :recovery_path
        )
        InventoryEntry = Data.define(:manifest, :directory, :manifest_path)

        attr_reader :root, :state_root

        def initialize(root: Mcweb::Plugins.default_root, state_root: nil,
                       reload_callback: nil, runtime_catalog: nil,
                       ruby_version: RUBY_VERSION, rails_version: Rails.version,
                       clock: -> { Time.now.utc })
          @root = Pathname(root).expand_path.cleanpath
          @state_root = Pathname(state_root || default_state_root).expand_path.cleanpath
          if contained_path?(@state_root, @root)
            raise LifecycleError, "marketplace state directory must remain outside the plugin root"
          end

          @reload_callback = reload_callback || -> { Mcweb::Plugins.reload!(root: @root) }
          @runtime_catalog = runtime_catalog || -> { Mcweb::Plugins.list }
          @ruby_version = ruby_version.to_s.freeze
          @rails_version = rails_version.to_s.freeze
          @clock = clock
          @journal = OperationJournal.new(path: @state_root.join("operations.jsonl"), clock:)
        end

        def install(package_path:, source:, expected_sha256:, expected_id: nil, allow_downgrade: false)
          with_operation(:install, plugin_id: expected_id) do |operation_id, context|
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
            validate_install_target!(manifest, active:, disabled:)
            validate_version_change!(manifest, active[manifest.id], allow_downgrade:)
            validate_candidate_dependencies!(manifest, active:, disabled:)

            target = managed_path(manifest.id)
            installed = active[manifest.id]
            setup_plan = load_setup_plan(stage, manifest)
            setup_managed = setup_plan || installed&.manifest&.setup
            previous_receipt = read_receipt(manifest.id, strict: installed && setup_managed)
            initial_setup_state = if setup_plan
              installed ? Setup::State.load(previous_receipt["setup"]) : Setup::State.empty
            end
            preserved_setup_state = installed ? previous_receipt["setup"] : nil
            phase = installed ? :upgrade : :install

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
                  ensure_runtime_state!(manifest, present: true)
                  write_receipt(
                    manifest: manifest,
                    status: "active",
                    operation_id: operation_id,
                    source: archive.source.to_h,
                    sha256: archive.sha256,
                    recovery_path: context[:recovery_path],
                    setup_state: completed_setup_state&.to_h || preserved_setup_state
                  )
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
              recovery_path: context[:recovery_path]
            )
          ensure
            FileUtils.rm_rf(stage) if stage&.exist?
          end
        end

        def disable(plugin_id:)
          transition_to_inactive(plugin_id:, action: :disable)
        end

        def enable(plugin_id:)
          with_operation(:enable, plugin_id:) do |operation_id, context|
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            raise LifecycleError, "plugin #{plugin_id} is already active" if active.key?(plugin_id)

            entry = disabled.fetch(plugin_id) do
              raise LifecycleError, "disabled plugin #{plugin_id} was not found"
            end
            ensure_managed_entry!(entry, disabled_path(plugin_id))
            target = managed_path(plugin_id)
            refuse_occupied_target!(target)
            validate_candidate_dependencies!(entry.manifest, active:, disabled: disabled.except(plugin_id))

            receipt = read_receipt(plugin_id, strict: entry.manifest.setup.present?)
            with_receipt_rollback(plugin_id) do
              move_with_runtime_rollback!(source: entry.directory, destination: target) do
                ensure_runtime_state!(entry.manifest, present: true)
                context.merge!(plugin_id:, version: entry.manifest.version)
                write_receipt(
                  manifest: entry.manifest,
                  status: "active",
                  operation_id: operation_id,
                  source: receipt["source"],
                  sha256: receipt["sha256"],
                  setup_state: receipt["setup"]
                )
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
              recovery_path: nil
            )
          end
        end

        def uninstall(plugin_id:)
          transition_to_inactive(plugin_id:, action: :uninstall)
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
                setup: receipt["setup"]
              }.compact.freeze
            end.freeze

            {
              plugins: plugins,
              errors: errors.freeze,
              operations: @journal.recent(limit: recent_operations)
            }.freeze
          end
        end

        private

        def transition_to_inactive(plugin_id:, action:)
          with_operation(action, plugin_id:) do |operation_id, context|
            plugin_id = validate_plugin_id!(plugin_id)
            active = active_inventory!
            disabled = disabled_inventory!
            entry = active[plugin_id] || disabled[plugin_id]
            raise LifecycleError, "plugin #{plugin_id} was not found" unless entry
            raise LifecycleError, "plugin #{plugin_id} is already disabled" if action == :disable && disabled.key?(plugin_id)

            expected_directory = active.key?(plugin_id) ? managed_path(plugin_id) : disabled_path(plugin_id)
            ensure_managed_entry!(entry, expected_directory)
            validate_no_dependants!(plugin_id, active.merge(disabled))
            destination = if action == :disable
              disabled_path(plugin_id)
            else
              quarantined_path(operation_id, plugin_id)
            end
            raise LifecycleError, "plugin lifecycle destination already exists" if destination.exist?

            receipt = read_receipt(plugin_id, strict: entry.manifest.setup.present?)
            result_status = action == :disable ? "disabled" : "uninstalled"
            setup_plan = load_setup_plan(entry.directory, entry.manifest) if action == :uninstall
            initial_setup_state = Setup::State.load(receipt["setup"]) if setup_plan

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
                  ensure_runtime_state!(entry.manifest, present: false)
                  write_receipt(
                    manifest: entry.manifest,
                    status: result_status,
                    operation_id: operation_id,
                    source: receipt["source"],
                    sha256: receipt["sha256"],
                    recovery_path: recovery_path,
                    setup_state: completed_setup_state&.to_h || receipt["setup"]
                  )
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
              recovery_path: recovery_path
            )
          end
        end

        def with_operation(action, plugin_id: nil)
          with_lock do
            operation_id = @journal.start(action:, plugin_id:)
            context = { plugin_id: plugin_id }
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
            raise
          end
        end

        def finish_journal(**attributes)
          @journal.finish(**attributes)
        rescue StandardError => e
          logger&.error("[mcweb.plugin_marketplace] unable to finish operation journal: #{e.class}: #{e.message}")
          nil
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
              yield completed_state
            end
          end
        end

        def managed_path(plugin_id)
          plugin_id = validate_plugin_id!(plugin_id)
          root.join(*plugin_id.split("/")).tap { |path| ensure_no_symlink_components!(path) }
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

        def write_receipt(manifest:, status:, operation_id:, source: nil, sha256: nil,
                          recovery_path: nil, setup_state: nil)
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
