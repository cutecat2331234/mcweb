# frozen_string_literal: true

require_relative "normalizer"

module Mcweb
  module PluginApi
    module V1
      # Explicit allow-list serializers for identity resources. These snapshots
      # intentionally omit email addresses, credentials, moderation notes and
      # other account internals even though deployment plugins are trusted.
      module IdentitySnapshot
        SCHEMA_VERSION = "1"

        module_function

        def user(user)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "identity.user",
            id: user.id,
            public_id: user.public_id,
            username: user.username,
            display_name: user.display_name,
            status: user.status,
            created_at: user.created_at,
            updated_at: user.updated_at
          )
        end

        def user_status(user)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "identity.user_status",
            id: user.id,
            public_id: user.public_id,
            status: user.status,
            active: user.active? && user.session_eligible?,
            banned: user.banned?,
            deleted: user.deleted?,
            session_eligible: user.session_eligible?
          )
        end

        def group(group, primary: nil)
          attributes = {
            schema_version: SCHEMA_VERSION,
            type: "identity.group",
            id: group.id,
            name: group.name,
            priority: group.priority,
            color_hex: group.color_hex,
            banner_text: group.banner_text,
            primary_default: group.is_primary_default?,
            permission_keys: group.permission_keys.sort
          }
          attributes[:primary] = primary unless primary.nil?
          Normalizer.call(attributes)
        end

        def permission_contribution(contribution)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "identity.permission_contribution",
            plugin_id: contribution.plugin_id,
            id: contribution.id,
            group: contribution.group,
            title_phrase: contribution.title_phrase,
            description_phrase: contribution.description_phrase,
            scope: contribution.scope,
            default: contribution.default
          )
        end

        def permission_decision(
          user:,
          permission_key:,
          allowed:,
          eligible:,
          reason:,
          sources:,
          contribution: nil
        )
          attributes = {
            schema_version: SCHEMA_VERSION,
            type: "identity.permission_decision",
            user_id: user.id,
            user_public_id: user.public_id,
            permission_key: permission_key,
            allowed: allowed,
            account_eligible: eligible,
            reason: reason,
            scope: contribution&.scope || "global",
            sources: sources
          }
          attributes[:contribution] = permission_contribution(contribution) if contribution
          Normalizer.call(attributes)
        end
      end
    end
  end
end
