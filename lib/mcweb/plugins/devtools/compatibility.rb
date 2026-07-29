# frozen_string_literal: true

require "rubygems"

require_relative "../loader"
require_relative "../manifest"

module Mcweb
  module Plugins
    module Devtools
      class Compatibility
        CAPABILITIES = %w[
          commerce.fulfillments.write
          commerce.extend
          commerce.events.read
          commerce.inventory.read
          commerce.inventory.write
          commerce.orders.read
          commerce.orders.write
          commerce.payments.read
          commerce.products.read
          commerce.refunds.read
          commerce.refunds.write
          forum.events.publish
          forum.events.read
          forum.extend
          forum.moderate
          forum.read
          forum.write
          identity.groups.read
          identity.groups.members.write
          identity.events.read
          identity.permissions.read
          identity.users.read
          identity.users.write
          plugin.jobs.enqueue
          plugin.jobs.read
          plugin.events.read
          plugin.mail.deliver
          plugin.mail.read
          plugin.notifications.deliver
          plugin.notifications.read
          plugin.settings.read
          plugin.settings.write
          plugin.storage.read
          plugin.storage.write
          plugin.webhooks.deliver
          plugin.webhooks.read
          site.features.read
          site.events.read
          site.settings.read
        ].freeze
        DEPRECATIONS = {}.freeze

        Result = Data.define(:warnings, :errors) do
          def to_h
            { warnings:, errors: }.freeze
          end
        end

        def initialize(manifest:, plugins_root: nil, target_api_version: nil)
          @manifest = manifest
          @plugins_root = Pathname(plugins_root).expand_path if plugins_root
          @target_api_version = (target_api_version || manifest.api_version).to_s
        end

        def call
          warnings = []
          errors = []
          validate_api_version(errors)
          validate_capabilities(warnings)
          validate_dependencies(errors)
          Result.new(warnings: warnings.freeze, errors: errors.freeze)
        end

        private

        def validate_api_version(errors)
          return if Manifest::SUPPORTED_API_VERSIONS.include?(@target_api_version)
          errors << issue(
            "unsupported_target_api",
            "target plugin API #{@target_api_version.inspect} is not supported"
          )
        end

        def validate_capabilities(warnings)
          @manifest.capabilities.each do |capability|
            if (replacement = DEPRECATIONS[capability])
              warnings << issue(
                "deprecated_capability",
                "#{capability} is deprecated; use #{replacement}",
                capability:
              )
            elsif !CAPABILITIES.include?(capability)
              warnings << issue(
                "unknown_capability",
                "#{capability} is not in the host API v#{@target_api_version} compatibility matrix",
                capability:
              )
            end
          end
        end

        def validate_dependencies(errors)
          return if @manifest.requires.empty?
          unless @plugins_root&.directory?
            errors << issue(
              "dependency_catalog_missing",
              "plugins root is required to validate declared dependencies"
            )
            return
          end

          catalog = dependency_catalog(errors)
          @manifest.requires.each do |plugin_id, requirement|
            dependency = catalog[plugin_id]
            unless dependency
              errors << issue(
                "dependency_missing",
                "dependency #{plugin_id} is not present in the plugins root",
                dependency: plugin_id
              )
              next
            end
            next if Gem::Requirement.new(requirement).satisfied_by?(dependency.version_object)

            errors << issue(
              "dependency_version_mismatch",
              "dependency #{plugin_id} #{dependency.version} does not satisfy #{requirement}",
              dependency: plugin_id,
              installed_version: dependency.version,
              requirement:
            )
          end
        end

        def dependency_catalog(errors)
          @plugins_root.glob("**/#{Loader::MANIFEST_NAME}").sort.each_with_object({}) do |path, result|
            manifest = Manifest.load_file(path)
            next if manifest.source_path == @manifest.source_path

            if result.key?(manifest.id)
              errors << issue(
                "duplicate_dependency",
                "plugins root contains duplicate manifests for #{manifest.id}",
                dependency: manifest.id
              )
              next
            end
            result[manifest.id] = manifest
          rescue ManifestError => e
            errors << issue(
              "invalid_dependency_manifest",
              "dependency manifest is invalid: #{e.message}",
              path: safe_path(path)
            )
          end
        end

        def safe_path(path)
          path.relative_path_from(@plugins_root).to_s.tr("\\", "/")
        rescue ArgumentError
          path.basename.to_s
        end

        def issue(code, message, **details)
          { code:, message:, details: }.freeze
        end
      end
    end
  end
end
