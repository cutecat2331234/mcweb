# frozen_string_literal: true

module Minecraft
  class GenerateLinkCode < ApplicationService
    CODE_TTL = 10.minutes
    CODE_LENGTH = 8

    def initialize(server:, minecraft_uuid:, minecraft_username:, identity_type: "java")
      @server = server
      @minecraft_uuid = minecraft_uuid
      @minecraft_username = minecraft_username
      @identity_type = identity_type
    end

    def call
      code = generate_code

      link_code = Minecraft::LinkCode.create!(
        server: @server,
        code_digest: digest_code(code),
        minecraft_uuid: @minecraft_uuid,
        minecraft_username: @minecraft_username,
        identity_type: @identity_type,
        expires_at: CODE_TTL.from_now
      )

      ServiceResult.success(link_code: link_code, code: code)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def generate_code
      SecureRandom.alphanumeric(CODE_LENGTH).upcase
    end

    def digest_code(code)
      Digest::SHA256.hexdigest(code.to_s.upcase)
    end
  end
end
