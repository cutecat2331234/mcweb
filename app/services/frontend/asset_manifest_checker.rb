# frozen_string_literal: true

require "json"
require "pathname"

module Frontend
  class AssetManifestChecker
    VITE_RUNTIME_KINDS = %w[inertia inertia_document].freeze
    HASHED_ASSET = /-[A-Za-z0-9_-]{8,}\.[A-Za-z0-9.]+\z/

    def initialize(
      manifest_path: ViteRuby.config.known_manifest_paths.first,
      output_directory: ViteRuby.config.build_output_dir,
      application_registry: Frontend::ApplicationRegistry.instance
    )
      @manifest_path = Pathname(manifest_path)
      @output_directory = Pathname(output_directory)
      @application_registry = application_registry
    end

    def call
      return failure("frontend_manifest_missing") unless @manifest_path.file?

      manifest = JSON.parse(@manifest_path.read(encoding: "UTF-8"))
      return failure("frontend_manifest_invalid") unless manifest.is_a?(Hash)

      required_entrypoints = vite_entrypoints
      return failure("frontend_manifest_entry_missing") unless
        required_entrypoints.all? { |entrypoint| manifest.key?(entrypoint) }

      referenced_files = []
      manifest.each_value do |entry|
        return failure("frontend_manifest_invalid") unless entry.is_a?(Hash)

        referenced_files.concat(Array(entry["file"]))
        referenced_files.concat(Array(entry["css"]))
        referenced_files.concat(Array(entry["assets"]))

        dependency_keys = Array(entry["imports"]) + Array(entry["dynamicImports"])
        return failure("frontend_manifest_reference_missing") unless
          dependency_keys.all? { |key| manifest.key?(key) }
      end

      referenced_files = referenced_files.filter_map do |value|
        value.to_s.presence
      end.uniq
      return failure("frontend_manifest_invalid") if referenced_files.empty?
      return failure("frontend_asset_path_invalid") unless referenced_files.all? do |relative_path|
        safe_asset_path?(relative_path)
      end
      return failure("frontend_asset_missing") unless referenced_files.all? do |relative_path|
        @output_directory.join(relative_path).file?
      end
      return failure("frontend_asset_unhashed") unless referenced_files.all? do |relative_path|
        HASHED_ASSET.match?(File.basename(relative_path))
      end

      {
        status: "ok",
        probe: "manifest_and_files",
        entrypoints: required_entrypoints.length,
        assets: referenced_files.length
      }
    rescue JSON::ParserError, EncodingError
      failure("frontend_manifest_invalid")
    rescue SystemCallError
      failure("frontend_manifest_unreadable")
    end

    private

    def vite_entrypoints
      @vite_entrypoints ||= @application_registry.applications
        .select { |application| VITE_RUNTIME_KINDS.include?(application.runtime_kind) }
        .map { |application| "entrypoints/#{application.entrypoint}.ts" }
        .uniq
        .sort
        .freeze
    end

    def safe_asset_path?(relative_path)
      path = Pathname(relative_path)
      return false if path.absolute? || relative_path.include?("\\")

      clean = path.cleanpath
      clean.to_s == relative_path && !clean.each_filename.include?("..")
    end

    def failure(error_code)
      { status: "error", error_code: error_code }
    end
  end
end
