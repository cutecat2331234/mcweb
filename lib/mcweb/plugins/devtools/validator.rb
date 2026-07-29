# frozen_string_literal: true

require "json"

require_relative "../contribution_registry"
require_relative "../job_contribution"
require_relative "../marketplace/file_health"
require_relative "../marketplace/package_metadata"
require_relative "../permission_contribution"
require_relative "../setting_schema"
require_relative "compatibility"
require_relative "error"
require_relative "report"
require_relative "support"

module Mcweb
  module Plugins
    module Devtools
      class Validator
        MAX_FILE_MANIFEST_BYTES = 8 * 1024 * 1024

        def initialize(path:, plugins_root: nil, target_api_version: nil)
          @path = path
          @plugins_root = plugins_root
          @target_api_version = target_api_version
        end

        def call
          directory = Support.plugin_directory(@path)
          manifest = Manifest.load_file(directory.join(Support::MANIFEST_NAME))
          checks = []
          errors = []
          warnings = []

          check_entrypoint(directory, manifest, checks, errors)
          check_contributions(manifest, checks, errors)
          check_package_metadata(directory, manifest, checks, errors)
          file_health = check_file_manifest(directory, checks, errors)
          compatibility = Compatibility.new(
            manifest:,
            plugins_root: @plugins_root,
            target_api_version: @target_api_version
          ).call
          errors.concat(compatibility.errors)
          warnings.concat(compatibility.warnings)
          checks << {
            name: "compatibility",
            status: compatibility.errors.empty? ? "passed" : "failed"
          }

          data = {
            plugin: manifest.to_h.except(:source_path),
            manifest_sha256: manifest.canonical_sha256,
            path: directory.to_s,
            checks:,
            file_health:
          }.compact
          if errors.empty?
            Report.success("plugin:validate", data:, warnings:)
          else
            Report.failure("plugin:validate", data:, warnings:, errors:)
          end
        rescue Error, ManifestError, Marketplace::Error => e
          failure(e)
        rescue JSON::ParserError => e
          failure(Error.new("invalid_file_manifest", "files.sha256 is invalid JSON: #{e.message}"))
        rescue StandardError => e
          failure(
            Error.new(
              "validation_failed",
              "plugin validation could not complete",
              details: { error_class: e.class.name }
            )
          )
        end

        private

        def check_entrypoint(directory, manifest, checks, errors)
          relative = manifest.entrypoint || Loader::DEFAULT_ENTRYPOINT
          entrypoint = directory.join(relative).cleanpath
          Support.ensure_contained!(entrypoint, directory)
          unless entrypoint.file?
            errors << issue("entrypoint_missing", "entrypoint #{relative} does not exist", path: relative)
            checks << { name: "entrypoint", status: "failed" }
            return
          end

          RubyVM::InstructionSequence.compile_file(entrypoint.to_s)
          checks << { name: "entrypoint", status: "passed", path: relative }
        rescue SyntaxError => e
          errors << issue(
            "entrypoint_syntax_error",
            "entrypoint contains invalid Ruby syntax",
            path: relative,
            detail: e.message.lines.first.to_s.strip
          )
          checks << { name: "entrypoint", status: "failed", path: relative }
        rescue Error => e
          errors << issue(e.code, e.message, **e.details)
          checks << { name: "entrypoint", status: "failed", path: relative }
        end

        def check_contributions(manifest, checks, errors)
          loaders = {
            "permissions" => -> { PermissionContributionLoader.load(manifest) },
            "settings" => -> { SettingSchemaLoader.load(manifest) },
            "jobs" => -> { JobContributionLoader.load(manifest) },
            "catalog" => -> { ContributionDocumentLoader.load(manifest) }
          }
          loaders.each do |name, loader|
            next unless manifest.contributions.key?(name)

            contribution = loader.call
            count =
              if contribution.respond_to?(:jobs)
                contribution.jobs.length
              elsif contribution.respond_to?(:properties)
                contribution.properties.length
              else
                Array(contribution).length
              end
            checks << {
              name: "contribution:#{name}",
              status: "passed",
              entries: count
            }
          rescue ManifestError => e
            errors << issue(
              "invalid_#{name}_contribution",
              e.message,
              path: manifest.contributions[name]
            )
            checks << { name: "contribution:#{name}", status: "failed" }
          end
        end

        def check_package_metadata(directory, manifest, checks, errors)
          path = directory.join(Support::PACKAGE_METADATA_NAME)
          unless path.file?
            checks << { name: "package_metadata", status: "not_present" }
            return
          end

          metadata = Marketplace::PackageMetadata.load_file(path)
          metadata.validate!(
            manifest:,
            ruby_version: RUBY_VERSION,
            rails_version: Rails.version
          )
          checks << { name: "package_metadata", status: "passed" }
        rescue Marketplace::Error => e
          errors << issue("invalid_package_metadata", e.message)
          checks << { name: "package_metadata", status: "failed" }
        end

        def check_file_manifest(directory, checks, errors)
          path = directory.join(Support::GENERATED_FILE_MANIFEST)
          unless path.file?
            checks << { name: "file_manifest", status: "not_present" }
            return
          end
          if path.size > MAX_FILE_MANIFEST_BYTES
            raise Error.new("file_manifest_too_large", "files.sha256 is too large")
          end

          expected = JSON.parse(path.read(encoding: Encoding::UTF_8))
          result = Marketplace::FileHealth.check(
            directory:,
            expected:,
            exclude_paths: [ Support::GENERATED_FILE_MANIFEST ]
          )
          checks << { name: "file_manifest", status: result.status }
          unless result.healthy?
            errors << issue(
              "file_manifest_mismatch",
              "plugin files do not match files.sha256",
              **result.to_h.except(:status)
            )
          end
          result.to_h
        end

        def failure(error)
          Report.failure(
            "plugin:validate",
            errors: [
              issue(
                error.respond_to?(:code) ? error.code : "invalid_plugin",
                error.message,
                **(error.respond_to?(:details) ? error.details : {})
              )
            ]
          )
        end

        def issue(code, message, **details)
          { code:, message:, details: }.freeze
        end
      end
    end
  end
end
