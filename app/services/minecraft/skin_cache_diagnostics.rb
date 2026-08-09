# frozen_string_literal: true

require "digest"

module Minecraft
  class SkinCacheDiagnostics < ApplicationService
    KINDS = %w[cache_files duplicate_uuids primary_accounts].freeze
    REQUIRED_ATTACHMENTS = %i[
      skin_texture_file skin_avatar_file skin_bust_file skin_full_file
    ].freeze

    def initialize(kind:)
      @kind = kind.to_s
    end

    def call
      return ServiceResult.failure(error: :skin_diagnostic_kind_invalid) unless @kind.in?(KINDS)

      ServiceResult.success(kind: @kind, **send("#{@kind}_result"))
    rescue ActiveRecord::ActiveRecordError, ActiveStorage::FileNotFoundError
      ServiceResult.failure(error: :skin_diagnostic_failed)
    end

    private

    def cache_files_result
      scanned = 0
      incomplete = 0
      missing_storage_objects = 0
      digest_mismatches = 0

      Minecraft::PlayerIdentity.active.bound.find_each do |identity|
        scanned += 1
        attachments = REQUIRED_ATTACHMENTS.map { |name| identity.public_send(name) }
        unless attachments.all?(&:attached?)
          incomplete += 1
          next
        end

        missing_storage_objects += attachments.count do |attachment|
          !attachment.blob.service.exist?(attachment.blob.key)
        end
        next unless identity.skin_texture_sha256.present?

        digest = Digest::SHA256.hexdigest(identity.skin_texture_file.download)
        digest_mismatches += 1 unless ActiveSupport::SecurityUtils.secure_compare(digest, identity.skin_texture_sha256)
      rescue ActiveStorage::FileNotFoundError
        missing_storage_objects += 1
      end

      {
        scanned: scanned,
        incomplete: incomplete,
        missing_storage_objects: missing_storage_objects,
        digest_mismatches: digest_mismatches
      }
    end

    def duplicate_uuids_result
      normalized_uuid = "LOWER(REPLACE(external_uuid, '-', ''))"
      groups = Minecraft::PlayerIdentity.active
        .group(:platform, Arel.sql(normalized_uuid))
        .having("COUNT(*) > 1")
        .count

      { duplicate_groups: groups.length, duplicate_records: groups.values.sum }
    end

    def primary_accounts_result
      rows = Minecraft::IdentityLink.active
        .group(:user_id)
        .pluck(
          :user_id,
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE primary_account = TRUE)")
        )
      invalid = rows.count { |_user_id, _link_count, primary_count| primary_count.to_i != 1 }

      { users_with_bindings: rows.length, invalid_primary_users: invalid }
    end
  end
end
