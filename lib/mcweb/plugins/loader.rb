# frozen_string_literal: true

require_relative "registry"
require "find"
require "pathname"

module Mcweb
  module Plugins
    class Loader
      MANIFEST_NAME = "mcweb_plugin.yml"
      DEFAULT_ENTRYPOINT = "plugin.rb"

      def initialize(root:, registry: Mcweb::Plugins.registry)
        @root = Pathname(root).expand_path
        @registry = registry
      end

      def load!
        return [] unless @root.directory?

        loaded = []
        load_outcomes = {}
        entries = manifest_entries
        preflight_failures = dependency_preflight_failures(entries)
        ordered_manifest_entries(entries).each do |manifest_path, manifest|
          before = @registry.ids
          preflight_failure = preflight_failures[manifest_path.to_s]
          if preflight_failure
            if preflight_failure.fetch(:register_inert)
              @registry.register(manifest)
              load_outcomes[manifest.id] = :dependency_failed
            else
              load_outcomes[manifest.id] = :failed
            end
            record_preflight_failure(manifest_path, manifest, preflight_failure)
            next
          end

          failed_dependencies = manifest.requires.keys.select do |dependency_id|
            load_outcomes[dependency_id].in?(%i[failed dependency_failed])
          end

          if failed_dependencies.any?
            # Register only the inert definition. boot! will mark it disabled
            # through the normal dependency diagnostics without executing any
            # code from an entrypoint whose prerequisite failed to load.
            @registry.register(manifest)
            load_outcomes[manifest.id] = :dependency_failed
            record_dependency_load_failure(manifest_path, manifest, failed_dependencies)
            next
          end

          entrypoint = resolve_entrypoint(manifest_path.dirname, manifest.entrypoint || DEFAULT_ENTRYPOINT)
          Mcweb::Plugins.with_loading_manifest(manifest) { Kernel.load(entrypoint.to_s) }
          unless (@registry.ids - before) == [ manifest.id ]
            raise LifecycleError, "entrypoint must register exactly #{manifest.id}"
          end

          load_outcomes[manifest.id] = :loaded
          loaded << manifest.id
        rescue StandardError, ScriptError => e
          (@registry.ids - (before || [])).each { |id| @registry.unregister(id) }
          load_outcomes[manifest.id] = :failed if manifest
          record_load_failure(manifest_path, e, plugin_id: manifest&.id)
        end
        loaded.freeze
      end

      private

      def manifest_entries
        manifest_paths.filter_map do |manifest_path|
          manifest = Manifest.load_file(manifest_path)
          PermissionContributionLoader.load(manifest)
          [ manifest_path, manifest ]
        rescue StandardError, ScriptError => e
          record_load_failure(manifest_path, e)
          nil
        end
      end

      def ordered_manifest_entries(entries)
        first_by_id = entries.each_with_object({}) do |entry, result|
          result[entry.last.id] ||= entry
        end
        state = {}
        ordered = []

        visit = lambda do |entry|
          key = entry.first.to_s
          return if state[key] == :done
          return if state[key] == :visiting

          state[key] = :visiting
          entry.last.requires.keys.sort.each do |dependency_id|
            dependency = first_by_id[dependency_id]
            visit.call(dependency) if dependency
          end
          state[key] = :done
          ordered << entry
        end

        entries.each { |entry| visit.call(entry) }
        ordered
      end

      def dependency_preflight_failures(entries)
        failures = {}
        grouped = entries.group_by { |(_, manifest)| manifest.id }

        grouped.each do |plugin_id, duplicates|
          next if duplicates.one?

          duplicates.each do |manifest_path, _manifest|
            failures[manifest_path.to_s] = {
              code: :duplicate_plugin_manifest,
              message: "duplicate manifest id #{plugin_id}",
              register_inert: false
            }
          end
        end

        unique_by_id = grouped.filter_map do |plugin_id, group|
          [ plugin_id, group.first ] if group.one?
        end.to_h

        dependency_cycle_ids(unique_by_id).each do |plugin_id|
          manifest_path, = unique_by_id.fetch(plugin_id)
          failures[manifest_path.to_s] = {
            code: :dependency_cycle,
            message: "entrypoint skipped because dependency cycle includes #{plugin_id}",
            register_inert: true
          }
        end

        unique_by_id.each_value do |manifest_path, manifest|
          next if failures.key?(manifest_path.to_s)

          mismatch = manifest.requires.find do |dependency_id, requirement_string|
            dependency_entry = unique_by_id[dependency_id]
            dependency_entry &&
              !Gem::Requirement.new(requirement_string).satisfied_by?(
                dependency_entry.last.version_object
              )
          end
          next unless mismatch

          dependency_id, requirement_string = mismatch
          dependency = unique_by_id.fetch(dependency_id).last
          failures[manifest_path.to_s] = {
            code: :dependency_version_mismatch,
            message: "entrypoint skipped because dependency #{dependency_id} " \
                     "#{dependency.version} does not satisfy #{requirement_string}",
            register_inert: true
          }
        end

        failures.freeze
      end

      def dependency_cycle_ids(unique_by_id)
        state = {}
        stack = []
        cycles = Set.new

        visit = lambda do |plugin_id|
          case state[plugin_id]
          when :done
            return
          when :visiting
            start = stack.index(plugin_id) || 0
            stack[start..].each { |id| cycles << id }
            return
          end

          state[plugin_id] = :visiting
          stack << plugin_id
          manifest = unique_by_id.fetch(plugin_id).last
          manifest.requires.each_key do |dependency_id|
            visit.call(dependency_id) if unique_by_id.key?(dependency_id)
          end
          stack.pop
          state[plugin_id] = :done
        end

        unique_by_id.each_key { |plugin_id| visit.call(plugin_id) }
        cycles
      end

      def record_load_failure(manifest_path, error, plugin_id: nil)
        @registry.record_diagnostic(
          level: :error,
          code: :plugin_load_failed,
          phase: :load,
          plugin_id: plugin_id,
          message: "#{manifest_path}: #{error.message}",
          exception: error
        )
      end

      def record_dependency_load_failure(manifest_path, manifest, dependency_ids)
        @registry.record_diagnostic(
          level: :error,
          code: :dependency_load_failed,
          phase: :load,
          plugin_id: manifest.id,
          message: "#{manifest_path}: entrypoint skipped because dependency loading failed: #{dependency_ids.sort.join(', ')}"
        )
      end

      def record_preflight_failure(manifest_path, manifest, failure)
        @registry.record_diagnostic(
          level: :error,
          code: failure.fetch(:code),
          phase: :load,
          plugin_id: manifest.id,
          message: "#{manifest_path}: #{failure.fetch(:message)}"
        )
      end

      def manifest_paths
        root_real = @root.realpath
        paths = []
        Find.find(root_real.to_s) do |path|
          candidate = Pathname(path)
          if candidate != root_real && candidate.symlink? && candidate.directory?
            Find.prune
          end
          next unless candidate.basename.to_s == MANIFEST_NAME

          begin
            real_path = candidate.realpath
          rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
            next
          end
          paths << real_path if contained_path?(real_path, root_real)
        end
        paths.uniq.sort_by(&:to_s)
      rescue SystemCallError, ArgumentError => e
        @registry.record_diagnostic(
          level: :error,
          code: :plugin_scan_failed,
          phase: :load,
          message: "#{@root}: #{e.message}",
          exception: e
        )
        []
      end

      def resolve_entrypoint(plugin_dir, relative_path)
        candidate = plugin_dir.join(relative_path).cleanpath
        raise ManifestError, "entrypoint does not exist: #{candidate}" unless candidate.file?

        root_real = plugin_dir.realpath
        candidate_real = candidate.realpath
        unless contained_path?(candidate_real, root_real)
          raise ManifestError, "entrypoint must remain inside the plugin directory"
        end
        candidate_real
      rescue Errno::ENOENT, Errno::EACCES => e
        raise ManifestError, "invalid entrypoint: #{e.message}"
      end

      def contained_path?(candidate, root)
        relative = candidate.relative_path_from(root)
        !relative.absolute? && relative.each_filename.first != ".."
      rescue ArgumentError
        false
      end
    end
  end
end
