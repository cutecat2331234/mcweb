# frozen_string_literal: true

module Minecraft
  class GenerateLinkCode < ApplicationService
    CODE_TTL = 10.minutes
    CODE_LENGTH = 8

    def initialize(server:, minecraft_uuid:, minecraft_username:, identity_type: "java", code_digest: nil)
      @server = server
      @minecraft_uuid = minecraft_uuid
      @minecraft_username = minecraft_username
      @identity_type = identity_type
      @code_digest = code_digest.presence
    end

    def call
      player_ref = Minecraft::PlayerRef.resolve(
        uuid: @minecraft_uuid,
        platform: @identity_type,
        username: @minecraft_username
      )

      access = Minecraft::AssertPlayerOnServer.call(server: @server, player_ref: player_ref)
      return access unless access.success?

      code = nil
      digest = @code_digest || digest_code(code = generate_code)

      link_code = Minecraft::LinkCode.create!(
        server: @server,
        code_digest: digest,
        minecraft_uuid: @minecraft_uuid,
        minecraft_username: @minecraft_username,
        identity_type: @identity_type,
        expires_at: CODE_TTL.from_now
      )

      ServiceResult.success(link_code: link_code, code: code, client_generated: @code_digest.present?)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def generate_code
      SecureRandom.alphanumeric(CODE_LENGTH).upcase
    end

    def digest_code(code)
      Minecraft::LinkCode.digest_code(code)
    end
  end
end
