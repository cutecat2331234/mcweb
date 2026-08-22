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
            .to_a
          represented_profile_ids = links.filter_map(&:player_profile_id).index_with(true)

          accounts = links.map { |link| serialize_link(link) }
          legacy_identities(context.user).each do |legacy_identity|
            next if represented_profile_ids.key?(legacy_identity.player_profile_id)

            accounts << serialize_legacy_identity(legacy_identity)
          end

          ::Identity::DataExporting::Contribution.new(
            documents: { "minecraft/accounts.json" => accounts }
          )
        end

        private

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
