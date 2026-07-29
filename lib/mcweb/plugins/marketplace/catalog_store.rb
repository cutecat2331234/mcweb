# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require_relative "../contribution_registry"
require_relative "../job_contribution"
require_relative "../permission_contribution"
require_relative "../setting_schema"
require_relative "error"
require_relative "file_health"

module Mcweb
  module Plugins
    module Marketplace
      # Persists only reviewed, bounded plugin metadata. Absolute paths, package
      # source credentials, runtime payloads, and plugin setting values are not
      # accepted by this boundary.
      class CatalogStore
        SHA256_PATTERN = /\A[0-9a-f]{64}\z/
        STATES = %w[active disabled rollback uninstalled].freeze
        CURRENT_STATES = (STATES - [ "rollback" ]).freeze
        DIAGNOSTIC_CODES = %w[
          catalog_record_missing
          contribution_catalog_invalid
          file_health_changed
          file_manifest_invalid
          filesystem_missing
          filesystem_status_mismatch
          package_digest_derived
          package_digest_invalid
          receipt_missing
          receipt_status_mismatch
          runtime_missing
          runtime_status_mismatch
          runtime_without_filesystem
        ].freeze

        SyncResult = Data.define(
          :release_id, :created, :changed, :contribution_count, :file_count,
          :health
        )

        def initialize(clock: -> { Time.current })
          @clock = clock
        end

        def available?
          %w[
            plugin_installations plugin_releases plugin_contributions plugin_files
          ].all? do |table|
            ActiveRecord::Base.connection.data_source_exists?(table)
          end
        rescue ActiveRecord::ActiveRecordError
          false
        end

        def plugin_ids
          return [] unless available?

          PluginInstallation.order(:plugin_id).pluck(:plugin_id).freeze
        end

        def synchronize!(
          plugin_id:,
          state:,
          manifest:,
          package_sha256: nil,
          expected_file_manifest: nil,
          directory: nil,
          operation_id: nil,
          diagnostics: [],
          rollback_release: nil
        )
          raise LifecycleError, "plugin catalog database is unavailable" unless available?

          plugin_id = normalize_plugin_id(plugin_id)
          state = normalize_state(state)
          validate_manifest!(manifest, plugin_id:)
          current = build_release_snapshot(
            manifest:,
            package_sha256:,
            expected_file_manifest:,
            directory:,
            diagnostics:
          )
          rollback = build_rollback_snapshot(rollback_release)

          PluginRelease.transaction do
            installation = PluginInstallation.lock.find_or_initialize_by(plugin_id:)
            installation.assign_attributes(installation_attributes(state:, manifest:))
            installation.save!

            release, created, changed = persist_release!(
              installation:,
              state:,
              operation_id:,
              snapshot: current
            )
            persist_release!(
              installation:,
              state: "rollback",
              operation_id:,
              snapshot: rollback
            ) if rollback

            SyncResult.new(
              release_id: release.id,
              created:,
              changed:,
              contribution_count: release.contributions.count,
              file_count: release.files.count,
              health: release.health
            )
          end
        end

        def mark_unavailable!(plugin_id:, state:, diagnostics:)
          return unless available?

          plugin_id = normalize_plugin_id(plugin_id)
          state = normalize_state(state)
          PluginRelease.transaction do
            installation = PluginInstallation.lock.find_or_initialize_by(plugin_id:)
            installation.assign_attributes(
              desired_state: desired_state(state),
              current_state: installation_state(state),
              current_version: state == "uninstalled" ? nil : installation.current_version,
              error_code: "plugin_catalog_unavailable",
              error_message: nil
            )
            installation.save!
            release = installation.releases.current.order(observed_at: :desc, id: :desc).first
            next unless release

            release.update!(
              state:,
              health: "unavailable",
              diagnostics: normalize_diagnostics(diagnostics),
              observed_at: @clock.call
            )
            release.files.update_all(
              health: "unavailable",
              observed_byte_size: nil,
              observed_sha256: nil,
              updated_at: @clock.call
            )
          end
        end

        private

        def build_rollback_snapshot(value)
          return unless value.respond_to?(:to_h)

          attributes = value.to_h.symbolize_keys
          manifest = attributes[:manifest]
          return unless manifest

          validate_manifest!(manifest, plugin_id: manifest.id)
          build_release_snapshot(
            manifest:,
            package_sha256: attributes[:package_sha256],
            expected_file_manifest: attributes[:expected_file_manifest],
            directory: attributes[:directory],
            diagnostics: attributes[:diagnostics] || []
          )
        end

        def build_release_snapshot(
          manifest:,
          package_sha256:,
          expected_file_manifest:,
          directory:,
          diagnostics:
        )
          manifest_descriptor = catalog_manifest_descriptor(manifest)
          manifest_sha256 = digest(manifest_descriptor)
          actual_manifest = read_actual_manifest(directory)
          expected_manifest = normalize_file_manifest(expected_file_manifest)
          package_digest_source = "receipt"
          normalized_diagnostics = normalize_diagnostics(diagnostics)

          raw_package_sha256 = package_sha256.to_s.downcase
          unless raw_package_sha256.match?(SHA256_PATTERN)
            if raw_package_sha256.present?
              normalized_diagnostics = merge_diagnostic(
                normalized_diagnostics,
                code: "package_digest_invalid",
                severity: "error"
              )
            end
            package_sha256 = digest(
              "manifest" => manifest_descriptor,
              "files" => expected_manifest || actual_manifest || { "files" => [] }
            )
            package_digest_source = "derived"
            normalized_diagnostics = merge_diagnostic(
              normalized_diagnostics,
              code: "package_digest_derived",
              severity: "warning"
            )
          end

          files, health = file_snapshots(
            expected_manifest:,
            actual_manifest:
          )
          descriptors = contribution_descriptors(manifest)
          {
            manifest:,
            manifest_descriptor:,
            manifest_sha256:,
            package_sha256: package_sha256.to_s.downcase,
            package_digest_source:,
            diagnostics: normalized_diagnostics,
            contributions: descriptors,
            files:,
            health:
          }.freeze
        end

        def persist_release!(installation:, state:, operation_id:, snapshot:)
          release = installation.releases.find_by(
            version: snapshot.fetch(:manifest).version,
            package_sha256: snapshot.fetch(:package_sha256)
          )
          release ||= installation.releases.find_by(
            version: snapshot.fetch(:manifest).version,
            manifest_sha256: snapshot.fetch(:manifest_sha256)
          )
          created = release.nil?
          release ||= installation.releases.build

          if CURRENT_STATES.include?(state)
            installation.releases.current.where.not(id: release.id).update_all(
              state: "rollback",
              updated_at: @clock.call
            )
          end

          attributes = {
            plugin_id: installation.plugin_id,
            version: snapshot.fetch(:manifest).version,
            api_version: snapshot.fetch(:manifest).api_version,
            state:,
            manifest_descriptor: snapshot.fetch(:manifest_descriptor),
            manifest_sha256: snapshot.fetch(:manifest_sha256),
            package_sha256: snapshot.fetch(:package_sha256),
            package_digest_source: snapshot.fetch(:package_digest_source),
            operation_id: operation_id.to_s.presence,
            health: snapshot.fetch(:health),
            diagnostics: snapshot.fetch(:diagnostics),
            observed_at: @clock.call
          }
          changed = created || attributes.any? do |key, value|
            release.public_send(key) != value
          end
          release.assign_attributes(attributes)
          release.save!
          replace_contributions!(release, snapshot.fetch(:contributions))
          replace_files!(release, snapshot.fetch(:files))
          [ release, created, changed ]
        end

        def replace_contributions!(release, descriptors)
          rows = descriptors.map do |descriptor|
            descriptor = canonicalize(descriptor)
            schema = contribution_schema(descriptor)
            {
              plugin_release_id: release.id,
              contribution_id: descriptor.fetch("id"),
              contribution_type: descriptor.fetch("type"),
              descriptor:,
              descriptor_sha256: digest(descriptor),
              schema_sha256: schema ? digest(schema) : nil,
              created_at: @clock.call,
              updated_at: @clock.call
            }
          end
          ids = rows.pluck(:contribution_id)
          release.contributions.where.not(contribution_id: ids).delete_all
          PluginContribution.upsert_all(
            rows,
            unique_by: :idx_plugin_contributions_release_id
          ) if rows.any?
        end

        def replace_files!(release, files)
          rows = files.map do |entry|
            entry.merge(
              plugin_release_id: release.id,
              created_at: @clock.call,
              updated_at: @clock.call
            )
          end
          paths = rows.pluck(:path)
          release.files.where.not(path: paths).delete_all
          PluginFile.upsert_all(
            rows,
            unique_by: :idx_plugin_files_release_path
          ) if rows.any?
        end

        def contribution_descriptors(manifest)
          generic = ContributionDocumentLoader.load(manifest).map do |entry|
            entry.to_h.except(:source)
          end
          permissions = PermissionContributionLoader.load(manifest).map do |entry|
            {
              plugin_id: manifest.id,
              type: "permission",
              id: entry.id,
              priority: 100,
              before: [],
              after: [],
              requires: [],
              conflicts: [],
              payload: entry.to_h.except(:plugin_id)
            }
          end
          settings = SettingSchemaLoader.load(manifest)
          if settings
            permissions << {
              plugin_id: manifest.id,
              type: "settings",
              id: "#{manifest.id.tr('/-', '._')}.settings.schema",
              priority: 100,
              before: [],
              after: [],
              requires: [],
              conflicts: [],
              payload: {
                schema_version: settings.version,
                groups: settings.groups.keys,
                fields: settings.properties.keys,
                required_fields: settings.required_keys
              },
              schema: settings.to_h
            }
          end
          jobs = JobContributionLoader.load(manifest)
          if jobs
            jobs.jobs.each_value do |job|
              permissions << {
                plugin_id: manifest.id,
                type: "job",
                id: "#{manifest.id.tr('/-', '._')}.job.#{job.key.tr('.', '_')}",
                priority: 100,
                before: [],
                after: [],
                requires: [],
                conflicts: [],
                payload: {
                  key: job.key,
                  max_attempts: job.max_attempts,
                  retry_wait_seconds: job.retry_wait_seconds,
                  lease_seconds: job.lease_seconds
                }
              }
            end
          end
          (generic + permissions)
            .sort_by { |entry| [ entry.fetch(:type), entry.fetch(:id) ] }
            .map(&:freeze)
            .freeze
        end

        def contribution_schema(descriptor)
          explicit = descriptor.delete("schema")
          return explicit if explicit

          payload = descriptor.fetch("payload", {})
          payload["schema"] if payload.is_a?(Hash)
        end

        def file_snapshots(expected_manifest:, actual_manifest:)
          expected = file_map(expected_manifest)
          actual = file_map(actual_manifest)
          if expected_manifest.nil?
            return [
              actual.values.map do |entry|
                file_row(entry, observed: entry, expected: false, health: "untracked")
              end.sort_by { |entry| entry.fetch(:path) }.freeze,
              actual.empty? ? "unavailable" : "untracked"
            ]
          end

          paths = (expected.keys + actual.keys).uniq.sort
          rows = paths.map do |path|
            expected_entry = expected[path]
            actual_entry = actual[path]
            if expected_entry && actual_entry
              health =
                if expected_entry == actual_entry
                  "healthy"
                else
                  "modified"
                end
              file_row(expected_entry, observed: actual_entry, expected: true, health:)
            elsif expected_entry
              file_row(
                expected_entry,
                observed: nil,
                expected: true,
                health: actual_manifest ? "missing" : "unavailable"
              )
            else
              file_row(actual_entry, observed: actual_entry, expected: false, health: "unknown")
            end
          end.freeze
          health =
            if actual_manifest.nil?
              "unavailable"
            elsif rows.all? { |entry| entry.fetch(:health) == "healthy" }
              "healthy"
            elsif rows.any? { |entry| entry.fetch(:health) == "missing" }
              "missing"
            else
              "changed"
            end
          [ rows, health ]
        end

        def file_row(entry, observed:, expected:, health:)
          {
            path: entry.fetch("path"),
            byte_size: entry.fetch("size"),
            sha256: entry.fetch("sha256"),
            expected:,
            observed_byte_size: observed&.fetch("size"),
            observed_sha256: observed&.fetch("sha256"),
            health:
          }.freeze
        end

        def read_actual_manifest(directory)
          return unless directory

          path = Pathname(directory)
          return unless path.directory?

          normalize_file_manifest(FileHealth.manifest(path))
        rescue StandardError
          nil
        end

        def normalize_file_manifest(value)
          return unless value.is_a?(Hash) && value["algorithm"] == "sha256"
          return unless value["files"].is_a?(Array)

          files = value["files"].map do |entry|
            return unless entry.is_a?(Hash)

            path = normalize_file_path(entry["path"])
            size = Integer(entry["size"])
            sha256 = entry["sha256"].to_s.downcase
            return if size.negative? || !sha256.match?(SHA256_PATTERN)

            { "path" => path, "size" => size, "sha256" => sha256 }.freeze
          rescue ArgumentError, TypeError
            return
          end
          return if files.pluck("path").uniq.length != files.length

          {
            "algorithm" => "sha256",
            "files" => files.sort_by { |entry| entry.fetch("path") }.freeze
          }.freeze
        end

        def file_map(value)
          Array(value&.fetch("files", [])).index_by { |entry| entry.fetch("path") }
        end

        def normalize_file_path(value)
          path = Pathname(value.to_s.tr("\\", "/")).cleanpath
          if path.absolute? || path.to_s == "." ||
              path.each_filename.any? { |part| part.in?(%w[. ..]) }
            raise IntegrityError, "plugin file catalog path is invalid"
          end

          path.to_s.tr("\\", "/")
        rescue ArgumentError
          raise IntegrityError, "plugin file catalog path is invalid"
        end

        def installation_attributes(state:, manifest:)
          {
            desired_state: desired_state(state),
            current_state: installation_state(state),
            current_version: state == "uninstalled" ? nil : manifest.version,
            edition: "ce",
            error_code: nil,
            error_message: nil
          }
        end

        def catalog_manifest_descriptor(manifest)
          canonicalize(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            api_version: manifest.api_version,
            requires: manifest.requires,
            capabilities: manifest.capabilities,
            contributions: manifest.contributions,
            entrypoint: manifest.entrypoint,
            setup: manifest.setup
          )
        end

        def desired_state(state)
          state == "active" ? "enabled" : state
        end

        def installation_state(state)
          state == "active" ? "enabled" : state
        end

        def normalize_plugin_id(value)
          id = value.to_s
          unless id.length <= Manifest::MAX_ID_LENGTH && id.match?(Manifest::ID_PATTERN)
            raise LifecycleError, "invalid plugin id"
          end

          id
        end

        def normalize_state(value)
          state = value.to_s
          return state if STATES.include?(state)

          raise LifecycleError, "invalid plugin release state"
        end

        def validate_manifest!(manifest, plugin_id:)
          unless manifest.is_a?(Manifest) && manifest.id == plugin_id
            raise LifecycleError, "plugin catalog manifest identity mismatch"
          end
        end

        def normalize_diagnostics(value)
          Array(value).first(100).filter_map do |entry|
            data = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : {}
            code = data["code"].to_s
            next unless DIAGNOSTIC_CODES.include?(code)

            {
              "code" => code,
              "severity" => data["severity"].to_s.in?(%w[warning error]) ?
                data["severity"].to_s : "warning"
            }.freeze
          end.uniq.freeze
        end

        def merge_diagnostic(diagnostics, code:, severity:)
          (diagnostics + [ { "code" => code, "severity" => severity }.freeze ])
            .uniq
            .freeze
        end

        def digest(value)
          Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
        end

        def canonicalize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, child), result|
              result[key.to_s] = canonicalize(child)
            end.sort.to_h
          when Array
            value.map { |child| canonicalize(child) }
          when String, Numeric, TrueClass, FalseClass, NilClass
            value
          else
            value.to_s
          end
        end
      end
    end
  end
end
