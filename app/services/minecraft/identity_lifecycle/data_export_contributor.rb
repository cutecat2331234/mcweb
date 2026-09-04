# frozen_string_literal: true

module Minecraft
  module IdentityLifecycle
    class DataExportContributor
      class << self
        def call(context:)
          links = Minecraft::IdentityLink
            .where(user_id: context.user.id)
            .includes(player_profile: :player_identities)
            .order(:linked_at, :id)
          represented_profile_ids = links.where.not(player_profile_id: nil).select(:player_profile_id)
          legacy = legacy_identities(context.user)
          legacy_with_profile = legacy.where.not(player_profile_id: nil).where.not(player_profile_id: represented_profile_ids)
          legacy_without_profile = legacy.where(player_profile_id: nil)
          declared_count = links.count + legacy_with_profile.count + legacy_without_profile.count

          accounts = ::Identity::DataExporting::StreamingDocument.new(
            declared_count:,
            format: :json_array
          ) do
            Enumerator.new do |records|
              stream_relation(links) { |link| records << serialize_link(link) }
              stream_relation(legacy_with_profile) { |identity| records << serialize_legacy_identity(identity) }
              stream_relation(legacy_without_profile) { |identity| records << serialize_legacy_identity(identity) }
            end
          end

          ::Identity::DataExporting::Contribution.new(
            documents: { "minecraft/accounts.json" => accounts }
          )
        end

        private

        def stream_relation(relation)
          relation.reorder(nil).find_in_batches(
            batch_size: ::Identity::DataExporting::RecordSerializer::DEFAULT_STREAM_BATCH_SIZE,
            order: :asc
          ) do |batch|
            batch.each { |record| yield record }
          end
        end

        def legacy_identities(user)
          Minecraft::Identity
            .where(user_id: user.id)
            .includes(player_profile: :player_identities)
            .order(:linked_at, :id)
        end

        def serialize_link(link)
          {
            "binding_type" => "identity_link",
            "player_id" => link.player_profile.public_id,
            "primary_account" => link.unlinked_at.nil? && link.primary_account?,
            "linked_at" => timestamp(link.linked_at),
            "unlinked_at" => timestamp(link.unlinked_at),
            "identity" => serialize_player_identity(link.player_profile.active_identity)
          }
        end

        def serialize_legacy_identity(legacy_identity)
          player_identity = legacy_identity.player_profile&.active_identity
          {
            "binding_type" => "legacy_identity",
            "player_id" => legacy_identity.player_profile&.public_id,
            "linked_at" => timestamp(legacy_identity.linked_at),
            "identity" => if player_identity
                            serialize_player_identity(player_identity)
                          else
                            {
                              "platform" => legacy_identity.identity_type,
                              "external_uuid" => legacy_identity.uuid,
                              "username" => legacy_identity.username,
                              "identity_type" => legacy_identity.identity_type
                            }
                          end
          }
        end

        def serialize_player_identity(identity)
          return nil unless identity

          {
            "platform" => identity.platform,
            "external_uuid" => identity.external_uuid,
            "username" => identity.username,
            "identity_type" => identity.identity_type,
            "valid_from" => timestamp(identity.valid_from)
          }
        end

        def timestamp(value)
          value&.iso8601
        end
      end
    end
  end
end
