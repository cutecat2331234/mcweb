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

    def allowed?(filename:, content_type: nil)
      ext = File.extname(filename.to_s).delete_prefix(".").downcase
      return false if ext.blank?

      return false unless extensions.include?(ext)

      return true if content_type.blank?

      expected = DEFAULT_CONTENT_TYPES[ext]
      return true if expected.blank?

      content_type.to_s == expected || content_type.to_s.start_with?("text/")
    end
  end
end
