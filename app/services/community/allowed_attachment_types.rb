# frozen_string_literal: true

module Community
  module AllowedAttachmentTypes
    DEFAULT_EXTENSIONS = %w[
      pdf txt md json csv zip 7z rar doc docx xls xlsx ppt pptx
    ].freeze

    DEFAULT_CONTENT_TYPES = {
      "pdf" => "application/pdf",
      "txt" => "text/plain",
      "md" => "text/markdown",
      "json" => "application/json",
      "csv" => "text/csv",
      "zip" => "application/zip",
      "7z" => "application/x-7z-compressed",
      "rar" => "application/vnd.rar",
      "doc" => "application/msword",
      "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "xls" => "application/vnd.ms-excel",
      "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "ppt" => "application/vnd.ms-powerpoint",
      "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    }.freeze

    module_function

    def extensions
      SiteSetting.get("forum.attachments.allowed_extensions", DEFAULT_EXTENSIONS.join(","))
        .to_s.split(",")
        .map { |ext| ext.to_s.strip.downcase.delete_prefix(".") }
        .reject(&:blank?)
        .uniq
    end

    def max_size
      mb = SiteSetting.get("forum.attachments.max_size_mb", "10").to_i
      [ mb, 1 ].max.megabytes
    end

    def inspect_file(filename:, io:, allowed_extensions: extensions, max_bytes: max_size)
      ext = File.extname(filename.to_s).delete_prefix(".").downcase
      return Community::AttachmentContentInspector::Result.new(status: :unsupported) if ext.blank?
      normalized_extensions = Array(allowed_extensions).map { |item| item.to_s.downcase.delete_prefix(".") }
      return Community::AttachmentContentInspector::Result.new(status: :unsupported) unless normalized_extensions.include?(ext)
      return Community::AttachmentContentInspector::Result.new(status: :unsupported) unless extensions.include?(ext)

      # A configured extension has no generic fallback: formats without a
      # byte-level inspector remain rejected instead of trusting request MIME.
      content_type = DEFAULT_CONTENT_TYPES[ext]
      return Community::AttachmentContentInspector::Result.new(status: :unsupported) unless content_type

      Community::AttachmentContentInspector.call(
        extension: ext,
        io: io,
        max_bytes: max_bytes,
        content_type: content_type
      )
    end

    def allowed?(filename:, io:)
      inspect_file(filename: filename, io: io).success?
    end

    def download_content_type(filename)
      ext = File.extname(filename.to_s).delete_prefix(".").downcase
      DEFAULT_CONTENT_TYPES.fetch(ext, "application/octet-stream")
    end
  end
end
