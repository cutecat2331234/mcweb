# frozen_string_literal: true

module Commerce
  class ImagePackTexturesController < ApplicationController
    ALLOWED_EXTENSIONS = %w[.png .webp .gif .jpg .jpeg].freeze

    def show
      pack_id = params[:pack_id].to_s
      segments = params[:texture_path].to_s.split("/").map(&:strip).reject(&:blank?)
      raise ActiveRecord::RecordNotFound if pack_id.blank? || segments.blank?
      raise ActiveRecord::RecordNotFound if segments.any? { |segment| segment.include?("..") }

      pack = Mcweb::ImagePackRegistry.find(pack_id)
      raise ActiveRecord::RecordNotFound unless pack

      root = pack["root"].presence
      raise ActiveRecord::RecordNotFound if root.blank?

      file_path = Mcweb::ImagePackRegistry.texture_path(pack_id, *segments)
      raise ActiveRecord::RecordNotFound unless file_path

      file = Pathname(file_path).cleanpath
      root_path = Pathname(root).cleanpath
      raise ActiveRecord::RecordNotFound unless Frontend::PathContainment.within_root?(file, root_path)
      raise ActiveRecord::RecordNotFound unless file.file?

      ext = file.extname.downcase
      raise ActiveRecord::RecordNotFound unless ALLOWED_EXTENSIONS.include?(ext)

      expires_in Rails.env.development? ? 0.seconds : 1.year, public: true
      return unless stale?(etag: Digest::SHA256.file(file).hexdigest, last_modified: file.mtime, public: true)

      send_file file, disposition: "inline", type: mime_type_for(ext)
    end

    private

    def mime_type_for(ext)
      {
        ".png" => "image/png",
        ".webp" => "image/webp",
        ".gif" => "image/gif",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg"
      }.fetch(ext, "application/octet-stream")
    end
  end
end
