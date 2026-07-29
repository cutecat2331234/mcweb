# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require "yaml"
require "zip"

require_relative "../marketplace/file_health"
require_relative "error"
require_relative "report"
require_relative "support"
require_relative "validator"

module Mcweb
  module Plugins
    module Devtools
      class Builder
        def initialize(path:, output: nil, include_tests: true)
          @path = path
          @output = output
          @include_tests = include_tests
        end

        def call
          source = Support.plugin_directory(@path)
          validation = Validator.new(path: source).call
          return rebind_failure(validation) unless validation.ok?

          manifest = Manifest.load_file(source.join(Support::MANIFEST_NAME))
          output_directory = Pathname(@output || source.join("dist")).expand_path
          output_directory.mkpath
          temporary = Pathname(Dir.mktmpdir("mcweb-plugin-build-"))
          stage = temporary.join("package")
          Support.copy_package_tree(
            source:,
            destination: stage,
            include_tests: @include_tests
          )
          write_package_metadata(stage, manifest)
          file_manifest = Marketplace::FileHealth.manifest(
            stage,
            exclude_paths: [ Support::GENERATED_FILE_MANIFEST ]
          )
          stage.join(Support::GENERATED_FILE_MANIFEST).write(
            "#{JSON.pretty_generate(file_manifest)}\n",
            encoding: Encoding::UTF_8
          )

          staged_validation = Validator.new(path: stage).call
          return rebind_failure(staged_validation) unless staged_validation.ok?

          artifact = output_directory.join(artifact_name(manifest))
          temporary_artifact = temporary.join(artifact.basename)
          write_reproducible_zip(stage, temporary_artifact)
          sha256 = Digest::SHA256.file(temporary_artifact).hexdigest
          FileUtils.mv(temporary_artifact, artifact, force: true)
          checksum = artifact.sub_ext("#{artifact.extname}.sha256")
          checksum.write("#{sha256}  #{artifact.basename}\n", encoding: Encoding::UTF_8)

          Report.success(
            "plugin:build",
            data: {
              plugin: manifest.to_h.except(:source_path),
              artifact: artifact.to_s,
              checksum_file: checksum.to_s,
              sha256:,
              bytes: artifact.size,
              file_count: file_manifest.fetch("files").length,
              includes_tests: @include_tests,
              reproducible_timestamp: Support::RELEASE_EPOCH.iso8601
            },
            warnings: validation.warnings
          )
        rescue Error, ManifestError, Marketplace::Error, Zip::Error => e
          Report.failure(
            "plugin:build",
            errors: [ {
              code: e.respond_to?(:code) ? e.code : "build_failed",
              message: e.message,
              details: e.respond_to?(:details) ? e.details : {}
            } ]
          )
        rescue StandardError => e
          Report.failure(
            "plugin:build",
            errors: [ {
              code: "build_failed",
              message: "plugin build could not complete",
              details: { error_class: e.class.name }
            } ]
          )
        ensure
          FileUtils.remove_entry(temporary) if temporary&.exist?
        end

        private

        def write_package_metadata(stage, manifest)
          major_api = Gem::Version.new(manifest.api_version).segments.first
          metadata = {
            "schema_version" => "1",
            "plugin" => {
              "id" => manifest.id,
              "version" => manifest.version
            },
            "compatibility" => {
              "plugin_api" => "~> #{major_api}.0",
              "ruby" => ">= #{RUBY_VERSION.split('.').first(2).join('.')}",
              "rails" => ">= #{Rails.version.split('.').first(2).join('.')}"
            }
          }
          stage.join(Support::PACKAGE_METADATA_NAME).write(
            YAML.dump(metadata),
            encoding: Encoding::UTF_8
          )
        end

        def write_reproducible_zip(stage, artifact)
          entries = stage.glob("**/*", File::FNM_DOTMATCH)
            .select(&:file?)
            .sort_by { |path| path.relative_path_from(stage).to_s.tr("\\", "/") }

          Zip::OutputStream.open(artifact.to_s, suppress_extra_fields: true) do |stream|
            entries.each do |path|
              relative = path.relative_path_from(stage).to_s.tr("\\", "/")
              entry = Zip::Entry.new(
                "",
                relative,
                compression_method: Zip::Entry::DEFLATED,
                compression_level: 9,
                time: Support::RELEASE_EPOCH
              )
              entry.fstype = Zip::FSTYPE_UNIX
              entry.unix_perms = 0o644
              stream.put_next_entry(entry)
              File.open(path, "rb") { |file| IO.copy_stream(file, stream) }
            end
          end
        end

        def artifact_name(manifest)
          "#{manifest.id.tr('/._', '-')}-#{manifest.version}.zip"
        end

        def rebind_failure(report)
          Report.failure(
            "plugin:build",
            data: report.data,
            warnings: report.warnings,
            errors: report.errors
          )
        end
      end
    end
  end
end
