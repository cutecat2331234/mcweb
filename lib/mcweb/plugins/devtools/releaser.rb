# frozen_string_literal: true

require "json"

require_relative "builder"
require_relative "error"
require_relative "report"
require_relative "support"

module Mcweb
  module Plugins
    module Devtools
      class Releaser
        def initialize(path:, output: nil, include_tests: true)
          @path = path
          @output = output
          @include_tests = include_tests
        end

        def call
          source = Support.plugin_directory(@path)
          manifest = Manifest.load_file(source.join(Support::MANIFEST_NAME))
          notes = release_notes(source, manifest.version)
          build = Builder.new(
            path: source,
            output: @output,
            include_tests: @include_tests
          ).call
          return rebind_failure(build) unless build.ok?

          artifact = Pathname(build.data.fetch("artifact"))
          notes_path = artifact.sub_ext(".md")
          notes_path.write(notes, encoding: Encoding::UTF_8)
          release_path = artifact.sub_ext(".release.json")
          release_document = {
            schema_version: "1",
            plugin: build.data.fetch("plugin"),
            artifact: artifact.basename.to_s,
            sha256: build.data.fetch("sha256"),
            bytes: build.data.fetch("bytes"),
            notes: notes_path.basename.to_s
          }
          release_path.write(
            "#{JSON.pretty_generate(release_document)}\n",
            encoding: Encoding::UTF_8
          )

          Report.success(
            "plugin:release",
            data: build.data.merge(
              "release_manifest" => release_path.to_s,
              "release_notes" => notes_path.to_s
            ),
            warnings: build.warnings
          )
        rescue Error, ManifestError => e
          Report.failure(
            "plugin:release",
            errors: [ {
              code: e.respond_to?(:code) ? e.code : "release_failed",
              message: e.message,
              details: e.respond_to?(:details) ? e.details : {}
            } ]
          )
        rescue StandardError => e
          Report.failure(
            "plugin:release",
            errors: [ {
              code: "release_failed",
              message: "plugin release could not complete",
              details: { error_class: e.class.name }
            } ]
          )
        end

        private

        def release_notes(source, version)
          changelog = source.join("CHANGELOG.md")
          unless changelog.file?
            raise Error.new("changelog_missing", "CHANGELOG.md is required for a release")
          end

          content = changelog.read(encoding: Encoding::UTF_8)
          heading = /^##\s+\[?#{Regexp.escape(version)}\]?(?:\s|$).*$/
          match = content.match(heading)
          unless match
            raise Error.new(
              "release_notes_missing",
              "CHANGELOG.md must contain a level-two heading for #{version}"
            )
          end
          tail = content[match.begin(0)..]
          next_heading = tail.index(/^##\s+/, match[0].length)
          notes = next_heading ? tail[0...next_heading] : tail
          "#{notes.rstrip}\n"
        end

        def rebind_failure(report)
          Report.failure(
            "plugin:release",
            data: report.data,
            warnings: report.warnings,
            errors: report.errors
          )
        end
      end
    end
  end
end
