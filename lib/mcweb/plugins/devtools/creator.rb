# frozen_string_literal: true

require "tmpdir"
require "yaml"

require_relative "../manifest"
require_relative "../setting_schema"
require_relative "error"
require_relative "report"
require_relative "support"

module Mcweb
  module Plugins
    module Devtools
      class Creator
        def initialize(plugin_id:, root:, name: nil, author: nil)
          @plugin_id = plugin_id.to_s
          @root = Pathname(root).expand_path
          @name = name.to_s.strip.presence
          @author = author.to_s.strip.presence
        end

        def call
          manifest = build_manifest
          destination = Support.destination_directory(root: @root, plugin_id: manifest.id)
          raise Error.new("destination_exists", "plugin destination already exists") if destination.exist?

          @root.mkpath
          temporary = Pathname(Dir.mktmpdir(".mcweb-plugin-create-", @root.to_s))
          generate(temporary, manifest)
          destination.dirname.mkpath
          File.rename(temporary, destination)
          temporary = nil

          files = destination.glob("**/*")
            .select(&:file?)
            .map { |path| path.relative_path_from(destination).to_s.tr("\\", "/") }
            .sort
          Report.success(
            "plugin:create",
            data: {
              plugin: manifest.to_h.except(:source_path),
              path: destination.to_s,
              files:
            }
          )
        rescue Error, ManifestError => e
          Report.failure(
            "plugin:create",
            errors: [ {
              code: e.respond_to?(:code) ? e.code : "invalid_manifest",
              message: e.message,
              details: e.respond_to?(:details) ? e.details : {}
            } ]
          )
        ensure
          FileUtils.remove_entry(temporary) if temporary&.exist?
        end

        private

        def build_manifest
          attributes = {
            "id" => @plugin_id,
            "name" => @name || human_name,
            "version" => "0.1.0",
            "api_version" => "1",
            "description" => "McWeb plugin #{@plugin_id}",
            "capabilities" => %w[
              forum.events.publish
              forum.events.read
              plugin.settings.read
            ],
            "contributions" => {
              "catalog" => "config/contributions.yml",
              "settings" => "config/settings.yml"
            },
            "entrypoint" => "plugin.rb"
          }
          attributes["author"] = @author if @author
          Manifest.from_hash(attributes)
        end

        def generate(directory, manifest)
          %w[config locales test].each { |name| directory.join(name).mkpath }
          write_yaml(directory.join(Support::MANIFEST_NAME), manifest_hash(manifest))
          directory.join("plugin.rb").write(entrypoint_source(manifest), encoding: Encoding::UTF_8)
          write_yaml(directory.join("config/settings.yml"), settings_document(manifest))
          write_yaml(directory.join("config/contributions.yml"), contribution_document(manifest))
          write_yaml(directory.join("locales/en.yml"), locale_document(manifest, locale: "en"))
          write_yaml(directory.join("locales/zh-CN.yml"), locale_document(manifest, locale: "zh-CN"))
          directory.join("test/contract_test.rb").write(contract_test_source(manifest), encoding: Encoding::UTF_8)
          directory.join("README.md").write(readme(manifest), encoding: Encoding::UTF_8)
          directory.join("CHANGELOG.md").write(changelog(manifest), encoding: Encoding::UTF_8)
        end

        def manifest_hash(manifest)
          manifest.to_h
            .except(:source_path)
            .compact
            .transform_keys(&:to_s)
            .transform_values { |value| stringify_hash(value) }
        end

        def settings_document(manifest)
          namespace = namespace_for(manifest)
          {
            "schema_version" => "1",
            "groups" => {
              "general" => {
                "title_phrase" => "#{namespace}.settings.groups.general.title",
                "position" => 10
              }
            },
            "schema" => {
              "$schema" => SettingSchema::DRAFT_URI,
              "type" => "object",
              "additionalProperties" => false,
              "required" => [],
              "properties" => {
                "enabled" => {
                  "type" => "boolean",
                  "default" => true,
                  "x-mcweb-title-phrase" => "#{namespace}.settings.enabled.title",
                  "x-mcweb-description-phrase" => "#{namespace}.settings.enabled.description",
                  "x-mcweb-group" => "general",
                  "x-mcweb-input" => "switch"
                }
              }
            },
            "migrations" => []
          }
        end

        def contribution_document(manifest)
          namespace = namespace_for(manifest)
          phrase_values = {
            "en" => {
              "#{namespace}.navigation.label" => manifest.name,
              "#{namespace}.page.title" => manifest.name,
              "#{namespace}.page.description" => "Plugin administration page",
              "#{namespace}.page.body" => "The plugin is installed and its contributions are active.",
              "#{namespace}.event.topic_seen.description" => "Emitted after a topic event is handled",
              "#{namespace}.settings.groups.general.title" => "General",
              "#{namespace}.settings.enabled.title" => "Enabled",
              "#{namespace}.settings.enabled.description" => "Enable event handling"
            },
            "zh-CN" => {
              "#{namespace}.navigation.label" => manifest.name,
              "#{namespace}.page.title" => manifest.name,
              "#{namespace}.page.description" => "插件管理页面",
              "#{namespace}.page.body" => "插件已安装，其贡献项处于活动状态。",
              "#{namespace}.event.topic_seen.description" => "主题事件处理完成后发出",
              "#{namespace}.settings.groups.general.title" => "常规",
              "#{namespace}.settings.enabled.title" => "启用",
              "#{namespace}.settings.enabled.description" => "启用事件处理"
            }
          }
          contributions = [
            {
              "type" => "navigation",
              "id" => "#{namespace}.navigation.admin",
              "payload" => {
                "surface" => "admin",
                "position" => "sidebar",
                "label_phrase" => "#{namespace}.navigation.label",
                "href" => "/admin/plugins/#{manifest.id}/overview"
              }
            },
            {
              "type" => "page",
              "id" => "#{namespace}.page.overview",
              "payload" => {
                "surface" => "admin",
                "path" => "/admin/plugins/#{manifest.id}/overview",
                "title_phrase" => "#{namespace}.page.title",
                "description_phrase" => "#{namespace}.page.description",
                "blocks" => [ {
                  "type" => "text",
                  "title_phrase" => "#{namespace}.page.title",
                  "body_phrase" => "#{namespace}.page.body"
                } ]
              }
            },
            {
              "type" => "event",
              "id" => "#{namespace}.event.topic_seen",
              "payload" => {
                "name" => "#{namespace}.topic_seen",
                "direction" => "emits",
                "schema_version" => "1",
                "description_phrase" => "#{namespace}.event.topic_seen.description"
              }
            }
          ]
          phrase_values.each do |locale, phrases|
            suffix = locale.downcase.tr("-", "_")
            contributions << {
              "type" => "translation",
              "id" => "#{namespace}.translation.#{suffix}",
              "payload" => {
                "locale" => locale,
                "phrases" => phrases
              }
            }
          end
          { "schema_version" => "1", "contributions" => contributions }
        end

        def locale_document(manifest, locale:)
          namespace = namespace_for(manifest)
          values = contribution_document(manifest)
            .fetch("contributions")
            .find { |entry| entry.dig("payload", "locale") == locale }
            .dig("payload", "phrases")
          { locale => values }
        end

        def entrypoint_source(manifest)
          namespace = namespace_for(manifest)
          <<~RUBY
            # frozen_string_literal: true

            Mcweb::Plugins.register do |plugin|
              plugin.on("forum.topic.created") do |event|
                enabled = plugin.api.settings.get("enabled", default: true)
                next unless enabled.success? && enabled.value

                plugin.api.events.publish(
                  "#{namespace}.topic_seen",
                  "source_event_id" => event.event_id,
                  "topic_id" => event.data["topic_id"]
                )
              end
            end
          RUBY
        end

        def contract_test_source(manifest)
          class_name = "#{constant_name(manifest.id)}ContractTest"
          <<~RUBY
            # frozen_string_literal: true

            require "test_helper"
            require "mcweb/plugins/devtools"

            class #{class_name} < ActiveSupport::TestCase
              PLUGIN_ROOT = Pathname(__dir__).join("..").expand_path

              test "manifest and contributions satisfy the host contract" do
                report = Mcweb::Plugins::Devtools::Validator.new(path: PLUGIN_ROOT).call

                assert_predicate report, :ok?, report.errors.inspect
                assert_equal "#{manifest.id}", report.data.dig("plugin", "id")
              end
            end
          RUBY
        end

        def readme(manifest)
          <<~MARKDOWN
            # #{manifest.name}

            Generated with `bin/mcweb-plugin create`.

            ## Development

            ```sh
            bin/mcweb-plugin validate . --json
            bin/mcweb-plugin test . --json
            bin/mcweb-plugin build . --json
            ```
          MARKDOWN
        end

        def changelog(manifest)
          <<~MARKDOWN
            # Changelog

            ## #{manifest.version} - Unreleased

            - Initial plugin scaffold.
          MARKDOWN
        end

        def write_yaml(path, value)
          path.write(YAML.dump(value), encoding: Encoding::UTF_8)
        end

        def namespace_for(manifest)
          manifest.id.tr("/-", "._")
        end

        def human_name
          @plugin_id.split("/").last.to_s.split(/[._-]/).map(&:capitalize).join(" ")
        end

        def constant_name(plugin_id)
          plugin_id.split(/[^a-zA-Z0-9]+/).map do |segment|
            normalized = segment.gsub(/\A\d+/, "")
            normalized.empty? ? "Plugin" : normalized[0].upcase + normalized[1..]
          end.join
        end

        def stringify_hash(value)
          case value
          when Hash
            value.to_h { |key, child| [ key.to_s, stringify_hash(child) ] }
          when Array
            value.map { |child| stringify_hash(child) }
          else
            value
          end
        end
      end
    end
  end
end
