# frozen_string_literal: true

module Minecraft
  class BuildFileSyncUrl < ApplicationService
    TTL = 1.hour

    def initialize(path:, purpose: "sync_files")
      @path = path.to_s
      @purpose = purpose
    end

    def call
      return ServiceResult.failure(error: "Path is required.") if @path.blank?

      resolved = Minecraft::SyncFilePath.resolve(@path)
      return ServiceResult.failure(error: "Path is not allowed.") unless resolved

      relative_path = resolved.relative_path_from(Rails.root).to_s

      verifier = Rails.application.message_verifier("minecraft.sync_files")
      token = verifier.generate({ path: relative_path, purpose: @purpose, exp: TTL.from_now.to_i })

      url = Rails.application.routes.url_helpers.minecraft_sync_file_url(
        token: token,
        host: default_host
      )

      ServiceResult.success(url: url, expires_in: TTL.to_i)
    end

    private

    def default_host
      Rails.application.routes.default_url_options[:host] ||
        ENV.fetch("MCWEB_PUBLIC_URL", "localhost:3000")
    end
  end
end
