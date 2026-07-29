# frozen_string_literal: true

require "zip"

module Frontend
  class ValidateTemplateArchive < ApplicationService
    MAX_ZIP_BYTES = 20.megabytes
    MAX_ENTRIES = 200
    ALLOWED_EXTENSIONS = %w[.css .json .png .jpg .jpeg .svg .webp .gif .woff .woff2 .html].freeze
    FORBIDDEN_EXTENSIONS = %w[.vue .js .ts .rb .erb .zip .exe .sh .bat].freeze
    FORBIDDEN_PATH_PATTERN = %r{(?:^|/)(?:admin|Admin|pages/Admin)(?:/|$)|\.\.}
    REQUIRED_MANIFEST_KEYS = %w[name key version scopes].freeze
    ALLOWED_SCOPES = Frontend::Template::SCOPES

    def initialize(archive_io:)
      @archive_io = archive_io
    end

    def call
      return failure(error: I18n.t("mcweb.user_copy.template_archive_empty")) if @archive_io.nil?

      entries = []
      total_size = 0
      manifest_data = nil

      Zip::File.open_buffer(@archive_io) do |zip|
        return failure(error: I18n.t("mcweb.user_copy.template_archive_empty")) if zip.entries.empty?
        if zip.entries.size > MAX_ENTRIES
          return failure(
            error: I18n.t("mcweb.user_copy.template_archive_too_many_files", count: MAX_ENTRIES)
          )
        end

        zip.each do |entry|
          name = normalize_entry_name(entry.name)
          next if name.blank?
          next if entry.directory? || name.end_with?("/")

          if forbidden_path?(name)
            return failure(
              error: I18n.t("mcweb.user_copy.template_archive_invalid_path", path: entry.name)
            )
          end
          unless allowed_entry?(name)
            return failure(
              error: I18n.t("mcweb.user_copy.template_archive_file_type", path: name)
            )
          end

          total_size += entry.size.to_i
          if total_size > MAX_ZIP_BYTES
            return failure(
              error: I18n.t(
                "mcweb.user_copy.template_archive_too_large",
                megabytes: MAX_ZIP_BYTES / 1.megabyte
              )
            )
          end

          entries << name
          manifest_data = parse_manifest(entry) if name == "manifest.json"
        end
      end

      return failure(error: I18n.t("mcweb.user_copy.template_manifest_missing")) if manifest_data.nil?

      manifest_errors = validate_manifest(manifest_data, entries)
      return failure(error: manifest_errors.join("；")) if manifest_errors.any?

      ServiceResult.success(
        manifest: manifest_data,
        entries: entries
      )
    rescue Zip::Error => e
      failure(error: I18n.t("mcweb.user_copy.template_archive_invalid_zip", error: e.message))
    end

    private

    def normalize_entry_name(name)
      name.to_s.delete_prefix("./").strip
    end

    def forbidden_path?(name)
      name.match?(FORBIDDEN_PATH_PATTERN)
    end

    def allowed_entry?(name)
      ext = File.extname(name).downcase
      return false if FORBIDDEN_EXTENSIONS.include?(ext)
      return true if name == "manifest.json"
      return ALLOWED_EXTENSIONS.include?(ext) if ext.present?

      false
    end

    def parse_manifest(entry)
      JSON.parse(entry.get_input_stream.read)
    rescue JSON::ParserError
      nil
    end

    def validate_manifest(manifest, entries)
      errors = []
      unless manifest.is_a?(Hash)
        return [ I18n.t("mcweb.user_copy.template_manifest_object") ]
      end

      REQUIRED_MANIFEST_KEYS.each do |key|
        if manifest[key].blank? && manifest[key.to_sym].blank?
          errors << I18n.t("mcweb.user_copy.template_manifest_key_missing", key: key)
        end
      end

      key = manifest["key"] || manifest[:key]
      unless key.to_s.match?(/\A[a-z0-9][a-z0-9-]*\z/)
        errors << I18n.t("mcweb.user_copy.template_manifest_key_invalid")
      end

      scopes = Array(manifest["scopes"] || manifest[:scopes]).map(&:to_s)
      errors << I18n.t("mcweb.user_copy.template_manifest_scopes_empty") if scopes.empty?
      scopes.each do |scope|
        if scope == "admin" || !ALLOWED_SCOPES.include?(scope)
          errors << I18n.t("mcweb.user_copy.template_manifest_scope_invalid", scope: scope)
        end
      end

      assets = manifest["assets"] || manifest[:assets] || {}
      Array(assets["css"] || assets[:css]).each do |css_path|
        unless entries.include?(css_path.to_s)
          errors << I18n.t("mcweb.user_copy.template_manifest_css_missing", path: css_path)
        end
      end

      %w[logo favicon].each do |asset_key|
        path = assets[asset_key] || assets[asset_key.to_sym]
        next if path.blank?

        unless entries.include?(path.to_s)
          errors << I18n.t(
            "mcweb.user_copy.template_manifest_asset_missing",
            kind: asset_key,
            path: path
          )
        end
      end

      slots = manifest["slots"] || manifest[:slots] || {}
      slots.each do |slot_name, path|
        unless path.to_s.start_with?("slots/") && path.to_s.end_with?(".html")
          errors << I18n.t(
            "mcweb.user_copy.template_manifest_slot_path_invalid",
            slot: slot_name
          )
        end
        unless entries.include?(path.to_s)
          errors << I18n.t("mcweb.user_copy.template_manifest_slot_missing", path: path)
        end
      end

      errors
    end

    def failure(error:)
      ServiceResult.failure(error: error)
    end
  end
end
