# frozen_string_literal: true

require "zip"
require "fileutils"

module Frontend
  class InstallTemplateArchive < ApplicationService
    def initialize(archive_io:, actor: nil, key_override: nil, manifest_overrides: {})
      @archive_io = archive_io
      @actor = actor
      @key_override = key_override
      @manifest_overrides = manifest_overrides
    end

    def call
      data = @archive_io.read
      @archive_io.rewind if @archive_io.respond_to?(:rewind)

      validation = Frontend::ValidateTemplateArchive.call(archive_io: StringIO.new(data))
      return validation unless validation.success?

      manifest = validation.value[:manifest].deep_stringify_keys
      manifest.merge!(@manifest_overrides.stringify_keys) if @manifest_overrides.present?
      manifest["key"] = @key_override if @key_override.present?
      key = manifest.fetch("key")
      Frontend::TemplateStorage.ensure_root!
      target = Frontend::TemplateStorage.path_for(key)
      FileUtils.rm_rf(target) if target.exist?

      checksum = Digest::SHA256.hexdigest(data)
      template = ::Frontend::Template.find_or_initialize_by(key: key)

      begin
        FileUtils.mkdir_p(target)
        extract_archive(data, target)
        template.assign_attributes(
          name: manifest.fetch("name"),
          version: manifest.fetch("version", "1.0.0"),
          scopes: Array(manifest.fetch("scopes")),
          manifest: manifest,
          checksum: checksum,
          status: "installed",
          installed_path: target.to_s,
          error_message: nil
        )
        template.save!
        log_audit(template, "installed")
        ServiceResult.success(template)
      rescue StandardError => e
        FileUtils.rm_rf(target) if target&.exist?
        if template.persisted?
          template.update!(status: "failed", error_message: e.message)
        end
        ServiceResult.failure(error: "安装失败：#{e.message}")
      end
    end

    private

    def extract_archive(data, target)
      root = target.cleanpath
      Zip::File.open_buffer(data) do |zip|
        zip.each do |entry|
          name = entry.name.to_s.delete_prefix("./")
          next if name.blank?
          next if entry.directory? || name.end_with?("/")

          dest = root.join(name).cleanpath
          raise "非法路径" unless dest.to_s.start_with?(root.to_s)

          FileUtils.mkdir_p(dest.dirname)
          File.binwrite(dest, entry.get_input_stream.read)
        end
      end
    end

    def log_audit(template, action)
      return unless @actor

      Administration::AuditLogger.call(
        actor: @actor,
        action: "frontend.template.#{action}",
        resource: template,
        metadata: { key: template.key, scopes: template.scopes }
      )
    end
  end
end
