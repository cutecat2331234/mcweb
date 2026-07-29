# frozen_string_literal: true

require "fileutils"
require "pathname"
require "time"

require_relative "../loader"
require_relative "../manifest"
require_relative "error"

module Mcweb
  module Plugins
    module Devtools
      module Support
        MANIFEST_NAME = Mcweb::Plugins::Loader::MANIFEST_NAME
        GENERATED_FILE_MANIFEST = "files.sha256"
        PACKAGE_METADATA_NAME = "mcweb_package.yml"
        RELEASE_EPOCH = Time.utc(2000, 1, 1).freeze
        FORBIDDEN_PATH_COMPONENTS = %w[
          .git .idea .vscode dist log logs node_modules storage tmp vendor
        ].freeze
        FORBIDDEN_FILE_NAMES = %w[
          .env .env.local .gitconfig .git-credentials
        ].freeze
        FORBIDDEN_EXTENSIONS = %w[
          .key .p12 .pfx .pem
        ].freeze

        module_function

        def plugin_directory(path)
          directory = Pathname(path).expand_path
          unless directory.directory?
            raise Error.new("plugin_directory_missing", "plugin directory does not exist")
          end
          manifest = directory.join(MANIFEST_NAME)
          unless manifest.file?
            raise Error.new(
              "manifest_missing",
              "plugin directory must contain #{MANIFEST_NAME}"
            )
          end

          directory.realpath
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
          raise Error.new("plugin_directory_unavailable", "plugin directory is unavailable")
        end

        def destination_directory(root:, plugin_id:)
          root = Pathname(root).expand_path
          destination = root.join(*plugin_id.split("/")).cleanpath
          ensure_contained!(destination, root)
          destination
        end

        def ensure_contained!(path, root)
          relative = Pathname(path).cleanpath.relative_path_from(Pathname(root).cleanpath)
          if relative.absolute? || relative.each_filename.first == ".."
            raise Error.new("path_escape", "path must remain inside the requested root")
          end
          true
        rescue ArgumentError
          raise Error.new("path_escape", "path must remain inside the requested root")
        end

        def package_file?(relative, include_tests:)
          components = relative.each_filename.to_a
          return false if components.any? { |part| FORBIDDEN_PATH_COMPONENTS.include?(part.downcase) }
          return false if FORBIDDEN_FILE_NAMES.include?(relative.basename.to_s.downcase)
          return false if FORBIDDEN_EXTENSIONS.include?(relative.extname.downcase)
          return false if !include_tests && components.first == "test"
          return false if relative.basename.to_s == GENERATED_FILE_MANIFEST
          return false if relative.basename.to_s.end_with?("~", ".log", ".tmp")

          true
        end

        def copy_package_tree(source:, destination:, include_tests:)
          source = Pathname(source).realpath
          destination = Pathname(destination)
          destination.mkpath
          paths = source.glob("**/*", File::FNM_DOTMATCH)
            .reject { |path| path.basename.to_s.in?(%w[. ..]) }
            .sort_by { |path| path.relative_path_from(source).to_s.tr("\\", "/") }

          paths.each do |path|
            raise Error.new("symlink_not_supported", "plugin package must not contain symbolic links") if path.symlink?

            relative = path.relative_path_from(source)
            next unless package_file?(relative, include_tests:)

            target = destination.join(relative)
            ensure_contained!(target, destination)
            if path.directory?
              target.mkpath
            elsif path.file?
              target.dirname.mkpath
              FileUtils.copy_file(path, target)
            else
              raise Error.new("unsupported_file", "plugin package contains an unsupported file")
            end
          end
          destination
        end
      end
    end
  end
end
