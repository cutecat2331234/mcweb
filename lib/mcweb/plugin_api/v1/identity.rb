# frozen_string_literal: true

require_relative "identity_snapshot"
require_relative "result"

module Mcweb
  module PluginApi
    module V1
      # Identity facade. Reads expose allow-listed snapshots; controlled writes
      # delegate to core identity services so account eligibility, delegation,
      # validation and audit behavior stay canonical.
      class Identity
        DEFAULT_LIMIT = 50
        MAX_LIMIT = 100
        MAX_SELECTOR_LENGTH = 255
        MAX_PERMISSION_KEY_LENGTH = 191
        PERMISSION_KEY_PATTERN = /\A[a-z][a-z0-9_.]*\z/

        def initialize(plugin_id: nil, permission_catalog: nil, capability_auditor: nil)
          @plugin_id = plugin_id&.to_s&.dup&.freeze
          @permission_catalog = permission_catalog
          @capability_auditor = capability_auditor
          freeze
        end

        def find_user(id: nil, public_id: nil)
          audit("identity.users.read")
          user, failure = resolve_user(id:, public_id:)
          failure || Result.success(IdentitySnapshot.user(user))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def user_status(id: nil, public_id: nil)
          audit("identity.users.read")
          user, failure = resolve_user(id:, public_id:)
          failure || Result.success(IdentitySnapshot.user_status(user))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def update_user(actor:, user:, attributes:)
          audit("identity.users.write")
          actor, failure = resolve_mutation_user(actor, role: "actor")
          return failure if failure

          user, failure = resolve_mutation_user(user, role: "user")
          return failure if failure

          service_result = ::Identity::UpdateProfile.call(
            actor:,
            user:,
            attributes:
          )
          identity_service_result(service_result) do |value|
            {
              user: IdentitySnapshot.user(value.fetch(:user)),
              changed: value.fetch(:changed)
            }
          end
        rescue StandardError
          Result.failure(code: "host_error", error: "identity operation failed")
        end

        def groups(limit: DEFAULT_LIMIT)
          audit("identity.groups.read")
          limit, failure = resolve_limit(limit)
          return failure if failure

          snapshots = Community::UserGroup.ordered.limit(limit).map do |group|
            IdentitySnapshot.group(group)
          end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def user_groups(id: nil, public_id: nil)
          audit("identity.groups.read")
          user, failure = resolve_user(id:, public_id:)
          return failure if failure

          memberships = user.group_memberships.includes(:user_group).to_a
          snapshots = memberships
            .sort_by do |membership|
              group = membership.user_group
              [ -group.priority.to_i, group.name.to_s, group.id ]
            end
            .map do |membership|
              IdentitySnapshot.group(
                membership.user_group,
                primary: membership.is_primary?
              )
            end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def add_group_member(actor:, user:, group:)
          mutate_group_membership(
            operation: :add_member,
            actor:,
            user:,
            group:
          )
        end

        def remove_group_member(actor:, user:, group:)
          mutate_group_membership(
            operation: :remove_member,
            actor:,
            user:,
            group:
          )
        end

        def set_primary_group(actor:, user:, group:)
          mutate_group_membership(
            operation: :set_primary,
            actor:,
            user:,
            group:
          )
        end

        def permission_contributions(limit: DEFAULT_LIMIT)
          audit("identity.permissions.read")
          limit, failure = resolve_limit(limit)
          return failure if failure

          contributions = if @permission_catalog && @plugin_id
            @permission_catalog
              .all
              .select { |contribution| contribution.plugin_id == @plugin_id }
              .first(limit)
          else
            []
          end
          Result.success(
            contributions.map { |contribution| IdentitySnapshot.permission_contribution(contribution) }
          )
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def permission_contribution(key:)
          audit("identity.permissions.read")
          permission_key, failure = resolve_permission_key(key)
          return failure if failure

          contribution = own_permission_contribution(permission_key)
          unless contribution
            return Result.failure(
              code: "not_found",
              error: "permission contribution not found"
            )
          end

          Result.success(IdentitySnapshot.permission_contribution(contribution))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def plugin_permission(id: nil, public_id: nil, key: nil)
          audit("identity.permissions.read")
          permission_key, failure = resolve_permission_key(key)
          return failure if failure

          contribution = own_permission_contribution(permission_key)
          unless contribution
            return Result.failure(
              code: "not_found",
              error: "permission contribution not found"
            )
          end

          user, failure = resolve_user(id:, public_id:)
          failure || permission_decision(user, permission_key, contribution:)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def permission(id: nil, public_id: nil, key: nil)
          audit("identity.permissions.read")
          permission_key, failure = resolve_permission_key(key)
          return failure if failure

          user, failure = resolve_user(id:, public_id:)
          return failure if failure

          permission_decision(
            user,
            permission_key,
            contribution: own_permission_contribution(permission_key)
          )
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        private

        def mutate_group_membership(operation:, actor:, user:, group:)
          audit("identity.groups.members.write")
          actor, failure = resolve_mutation_user(actor, role: "actor")
          return failure if failure

          user, failure = resolve_mutation_user(user, role: "user")
          return failure if failure

          group, failure = resolve_mutation_group(group)
          return failure if failure

          service_result = ::Identity::ApplyGroupMutation.call(
            actor:,
            operation:,
            group:,
            user:
          )
          identity_service_result(service_result) do
            membership = Community::GroupMembership.find_by(
              user:,
              user_group: group
            )
            {
              user: IdentitySnapshot.user(user.reload),
              group: IdentitySnapshot.group(
                group.reload,
                primary: membership&.reload&.is_primary? || false
              ),
              member: membership.present?
            }
          end
        rescue StandardError
          Result.failure(code: "host_error", error: "identity operation failed")
        end

        def identity_service_result(service_result)
          if service_result.success?
            Result.success(yield(service_result.value))
          else
            code = service_result.code.to_s
            code = "service_failure" unless code.match?(/\A[a-z][a-z0-9_]*\z/)
            Result.failure(
              code:,
              error: "identity operation was rejected",
              errors: service_result.errors
            )
          end
        end

        def resolve_mutation_user(value, role:)
          unless value.is_a?(::User) && value.persisted?
            return [
              nil,
              Result.failure(
                code: "invalid_#{role}",
                error: "a persisted #{role} is required"
              )
            ]
          end

          [ value, nil ]
        end

        def resolve_mutation_group(value)
          group =
            if value.is_a?(Community::UserGroup) && value.persisted?
              value
            else
              id = Integer(value, exception: false)
              Community::UserGroup.find_by(id:) if id&.positive?
            end
          return [ group, nil ] if group

          [
            nil,
            Result.failure(
              code: "invalid_group",
              error: "a persisted group is required"
            )
          ]
        end

        def permission_decision(user, permission_key, contribution: nil)
          eligible = user.session_eligible?
          granted = user.permission?(permission_key)
          sources = permission_sources(user, permission_key)
          allowed = eligible && granted
          reason =
            if user.deleted?
              "account_deleted"
            elsif user.banned?
              "account_banned"
            elsif granted
              permission_grant_reason(user, sources)
            else
              "not_granted"
            end

          Result.success(IdentitySnapshot.permission_decision(
            user:,
            permission_key:,
            allowed:,
            eligible:,
            reason:,
            sources:,
            contribution:
          ))
        end

        def own_permission_contribution(permission_key)
          return unless @permission_catalog && @plugin_id

          contribution = @permission_catalog.find(permission_key)
          contribution if contribution&.plugin_id == @plugin_id
        end

        def audit(capability)
          @capability_auditor&.call(capability)
        end

        def resolve_user(id:, public_id:)
          selector, failure = resolve_selector(id:, public_id:)
          return [ nil, failure ] if failure

          user =
            if selector.fetch(:kind) == :id
              ::User.find_by(id: selector.fetch(:value))
            else
              ::User.find_by(public_id: selector.fetch(:value))
            end
          return [ user, nil ] if user

          [ nil, Result.failure(code: "not_found", error: "user not found") ]
        end

        def resolve_selector(id:, public_id:)
          unless id.nil? ^ public_id.nil?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "provide exactly one of id or public_id"
            ) ]
          end

          if id
            numeric_id = Integer(id, exception: false)
            unless numeric_id&.positive?
              return [ nil, Result.failure(
                code: "invalid_argument",
                error: "id must be a positive integer"
              ) ]
            end
            return [ { kind: :id, value: numeric_id }, nil ]
          end

          value = public_id.to_s
          unless value.length.between?(1, MAX_SELECTOR_LENGTH)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "public_id must be between 1 and #{MAX_SELECTOR_LENGTH} characters"
            ) ]
          end

          [ { kind: :public_id, value: }, nil ]
        end

        def resolve_limit(value)
          limit = Integer(value, exception: false)
          unless limit&.between?(1, MAX_LIMIT)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "limit must be between 1 and #{MAX_LIMIT}"
            ) ]
          end

          [ limit, nil ]
        end

        def resolve_permission_key(value)
          key = value.to_s
          unless key.length.between?(1, MAX_PERMISSION_KEY_LENGTH) &&
              key.match?(PERMISSION_KEY_PATTERN)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "permission key is invalid"
            ) ]
          end

          [ key, nil ]
        end

        def permission_sources(user, permission_key)
          sources = []
          if user.account_owner?
            sources << {
              type: "account",
              key: "owner",
              name: "Owner"
            }
          end

          user.roles
            .joins(:permissions)
            .where(permissions: { key: permission_key })
            .distinct
            .order(:key, :id)
            .each do |role|
              sources << {
                type: "role",
                id: role.id,
                key: role.key,
                name: role.name
              }
            end

          primary_by_group_id = user.group_memberships
            .pluck(:community_user_group_id, :is_primary)
            .to_h
          user.user_groups.ordered.each do |group|
            next unless group.permission_keys.include?(permission_key)

            sources << {
              type: "group",
              id: group.id,
              name: group.name,
              primary: primary_by_group_id.fetch(group.id, false)
            }
          end

          sources
        end

        def permission_grant_reason(user, sources)
          return "owner_override" if user.account_owner?
          return "granted_by_role_and_group" if source_type?(sources, "role") &&
            source_type?(sources, "group")
          return "granted_by_role" if source_type?(sources, "role")
          return "granted_by_group" if source_type?(sources, "group")

          "granted_by_core_policy"
        end

        def source_type?(sources, type)
          sources.any? { |source| source.fetch(:type) == type }
        end
      end
    end
  end
end
