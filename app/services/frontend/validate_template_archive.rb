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
      return failure(error: "模板包为空") if @archive_io.nil?

      entries = []
      total_size = 0
      manifest_data = nil

      Zip::File.open_buffer(@archive_io) do |zip|
        return failure(error: "模板包为空") if zip.entries.empty?
        return failure(error: "模板包文件过多（最多 #{MAX_ENTRIES} 个）") if zip.entries.size > MAX_ENTRIES

        zip.each do |entry|
          name = normalize_entry_name(entry.name)
          next if name.blank?

          return failure(error: "非法路径：#{entry.name}") if forbidden_path?(name)
          return failure(error: "不允许的文件类型：#{name}") unless allowed_entry?(name)

          total_size += entry.size.to_i
          return failure(error: "模板包过大（最大 #{MAX_ZIP_BYTES / 1.megabyte}MB）") if total_size > MAX_ZIP_BYTES

          entries << name
          manifest_data = parse_manifest(entry) if name == "manifest.json"
        end
      end

      return failure(error: "缺少 manifest.json") if manifest_data.nil?

      manifest_errors = validate_manifest(manifest_data, entries)
      return failure(error: manifest_errors.join("；")) if manifest_errors.any?

      ServiceResult.success(
        manifest: manifest_data,
        entries: entries
      )
    rescue Zip::Error => e
      failure(error: "无效的 ZIP 文件：#{e.message}")
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
        return [ "manifest.json 必须是 JSON 对象" ]
      end

      REQUIRED_MANIFEST_KEYS.each do |key|
        errors << "manifest 缺少 #{key}" if manifest[key].blank? && manifest[key.to_sym].blank?
      end

      key = manifest["key"] || manifest[:key]
      errors << "manifest key 格式无效" unless key.to_s.match?(/\A[a-z0-9][a-z0-9-]*\z/)

      scopes = Array(manifest["scopes"] || manifest[:scopes]).map(&:to_s)
      errors << "manifest scopes 不能为空" if scopes.empty?
      scopes.each do |scope|
        errors << "不允许的 scope：#{scope}" if scope == "admin" || !ALLOWED_SCOPES.include?(scope)
      end

      assets = manifest["assets"] || manifest[:assets] || {}
      Array(assets["css"] || assets[:css]).each do |css_path|
        errors << "manifest 引用的 CSS 不存在：#{css_path}" unless entries.include?(css_path.to_s)
      end

      %w[logo favicon].each do |asset_key|
        path = assets[asset_key] || assets[asset_key.to_sym]
        next if path.blank?

        errors << "manifest 引用的 #{asset_key} 不存在：#{path}" unless entries.include?(path.to_s)
      end

      slots = manifest["slots"] || manifest[:slots] || {}
      slots.each do |slot_name, path|
        unless path.to_s.start_with?("slots/") && path.to_s.end_with?(".html")
          errors << "slots.#{slot_name} 必须位于 slots/ 且为 .html 文件"
        end
        errors << "manifest 引用的 slot 不存在：#{path}" unless entries.include?(path.to_s)
      end

      errors
    end

    def failure(error:)
      ServiceResult.failure(error: error)
    end
  end
end
