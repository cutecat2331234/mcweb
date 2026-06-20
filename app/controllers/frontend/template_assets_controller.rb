# frozen_string_literal: true

module Frontend
  class TemplateAssetsController < ApplicationController
    def show
      template = Frontend::Template.installed.find_by!(key: params[:template_key])
      relative = params[:path].to_s
      raise ActiveRecord::RecordNotFound if relative.blank? || relative.include?("..")

      file = Pathname(template.installed_path).join(relative).cleanpath
      root = Pathname(template.installed_path).cleanpath
      raise ActiveRecord::RecordNotFound unless Frontend::PathContainment.within_root?(file, root) && file.file?

      ext = file.extname.downcase
      raise ActiveRecord::RecordNotFound unless Frontend::ValidateTemplateArchive::ALLOWED_EXTENSIONS.include?(ext)

      expires_in Rails.env.development? ? 0.seconds : 1.year, public: true
      return unless stale?(etag: Digest::SHA256.file(file).hexdigest, last_modified: file.mtime, public: true)

      send_data File.binread(file), disposition: "inline", type: mime_type_for(ext), filename: file.basename.to_s
    end

    private

    def mime_type_for(ext)
      {
        ".css" => "text/css",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".svg" => "image/svg+xml",
        ".webp" => "image/webp",
        ".gif" => "image/gif",
        ".woff" => "font/woff",
        ".woff2" => "font/woff2",
        ".html" => "text/html"
      }.fetch(ext, "application/octet-stream")
    end
  end
end
