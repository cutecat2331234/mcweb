# frozen_string_literal: true

require "digest"
require "stringio"

module Minecraft
  class RebuildSkinDerivatives < ApplicationService
    def initialize(actor:)
      @actor = actor
    end

    def call
      return ServiceResult.failure(error: :skin_refresh_actor_required) unless @actor

      scanned = 0
      rebuilt = 0
      skipped = 0
      failed = 0

      Minecraft::PlayerIdentity.active.bound.find_each do |identity|
        scanned += 1
        unless identity.skin_texture_file.attached?
          skipped += 1
          next
        end

        result = Minecraft::SkinDerivativeBuilder.call(
          payload: identity.skin_texture_file.download,
          model: identity.skin_model
        )
        unless result.success?
          failed += 1
          next
        end

        attach_derivatives!(identity, result.value)
        rebuilt += 1
      rescue ActiveStorage::FileNotFoundError, ActiveRecord::ActiveRecordError
        failed += 1
      end

      ServiceResult.success(scanned: scanned, rebuilt: rebuilt, skipped: skipped, failed: failed)
    end

    private

    def attach_derivatives!(identity, derivatives)
      blobs = []
      ActiveRecord::Base.transaction do
        identity.lock!
        {
          avatar: :skin_avatar_file,
          bust: :skin_bust_file,
          full: :skin_full_file
        }.each do |kind, attachment_name|
          derivative = derivatives.fetch(kind)
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(derivative.fetch(:payload)),
            filename: "minecraft-#{identity.id}-#{kind}-#{derivative.fetch(:sha256).first(12)}.png",
            content_type: "image/png",
            identify: false,
            metadata: {
              "minecraft_texture_kind" => kind.to_s,
              "sha256" => derivative.fetch(:sha256),
              "width" => derivative[:width],
              "height" => derivative[:height]
            }.compact
          )
          blobs << blob
          identity.public_send(attachment_name).attach(blob)
        end
        identity.update!(skin_cache_version: identity.skin_cache_version + 1)
        Administration::AuditLogger.call(
          actor: @actor,
          action: "minecraft.skin_derivatives_rebuilt",
          resource: identity,
          metadata: { cache_version: identity.skin_cache_version }
        )
      end
    rescue StandardError
      blobs.each { |blob| blob.purge unless blob.attachments.exists? }
      raise
    end
  end
end
