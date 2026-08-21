# frozen_string_literal: true

module Commerce
  class HighRiskMembershipAction < ApplicationService
    ACTIONS = %w[membership.grant membership.revoke].freeze

    class << self
      def authorize(**args)
        new(**args).authorize
      end
    end

    def initialize(actor:, action:, user: nil, membership_type: nil, membership: nil,
                   grant_game_permissions: true, revoke_game_permissions: true,
                   request_id:, reason:, authorization_token: nil, confirmation: nil,
                   ip_address: nil, user_agent: nil)
      @actor = actor
      @action = action.to_s
      @membership = membership
      @user = user || membership&.user
      @membership_type = membership_type || membership&.membership_type
      @grant_game_permissions = ActiveModel::Type::Boolean.new.cast(grant_game_permissions)
      @revoke_game_permissions = ActiveModel::Type::Boolean.new.cast(revoke_game_permissions)
      @request_id = Commerce::HighRiskActionAuthorization.normalize_request_id(request_id)
      @reason = Commerce::HighRiskActionAuthorization.normalize_reason(reason)
      @authorization_token = authorization_token.to_s
      @confirmation = confirmation.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def authorize
      with_fresh_authorized_actor { authorize_under_permission_lock }
    end

    def authorize_under_permission_lock
      failure = validation_failure
      return failure if failure

      auth = Commerce::HighRiskActionAuthorization.issue(
        actor: @actor,
        action: @action,
        targets: targets,
        state: current_state,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      )
      return auth if auth.failure?

      ServiceResult.success(
        auth.value.merge(
          preview: preview,
          target: target_summary
        )
      )
    end

    def call
      with_fresh_authorized_actor { call_under_permission_lock }
    end

    def call_under_permission_lock
      failure = validation_failure
      return failure if failure

      @request_fingerprint = request_fingerprint
      existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
      return idempotency_result(existing) if existing
      return ServiceResult.failure(error: "high_risk_authorization_invalid") if @authorization_token.blank?
      unless Commerce::HighRiskActionAuthorization.confirmation_valid?(
        @confirmation,
        action: @action,
        targets: targets,
        request_id: @request_id
      )
        return ServiceResult.failure(error: "high_risk_confirmation_invalid")
      end

      result = nil
      operation = nil
      Commerce::HighRiskOperation.transaction(requires_new: true) do
        lock_targets!
        existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
        return idempotency_result(existing) if existing

        state = current_state
        unless Commerce::HighRiskActionAuthorization.valid?(
          @authorization_token,
          actor: @actor,
          action: @action,
          targets: targets,
          state: state,
          attributes: attributes,
          request_id: @request_id,
          reason: @reason
        )
          return ServiceResult.failure(error: "high_risk_authorization_invalid")
        end

        before_state = state
        result = apply_action
        raise ActiveRecord::Rollback if result.failure?

        resource = result.value[:membership]
        after_state = membership_state(resource)
        operation = Commerce::HighRiskOperation.create!(
          actor: @actor,
          target_user: @user,
          action: @action,
          request_id: @request_id,
          request_fingerprint: @request_fingerprint,
          authorization_digest: Commerce::HighRiskActionAuthorization.authorization_digest(
            @authorization_token
          ),
          resource_type: resource.class.name,
          resource_id: resource.id,
          resource_public_id: resource.try(:public_id),
          reason: @reason,
          target_snapshot: targets,
          before_state: before_state,
          after_state: after_state,
          metadata: {
            membership_id: resource.id,
            membership_type_id: @membership_type.id,
            confirmation_method: "signed_typed_challenge",
            request_id: @request_id
          }
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.#{@action.tr('.', '_')}",
          resource: resource,
          metadata: {
            high_risk_operation_id: operation.id,
            request_id: @request_id,
            target_user_id: @user.id,
            membership_type_id: @membership_type.id,
            confirmation_method: "signed_typed_challenge"
          },
          before_state: before_state,
          after_state: after_state,
          ip_address: @ip_address,
          user_agent: @user_agent,
          reason: @reason
        )
      end
      return result if result&.failure?

      ServiceResult.success(
        membership: result.value[:membership].reload,
        operation: operation,
        request_id: @request_id,
        idempotent: false
      )
    rescue ActiveRecord::RecordNotUnique
      existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
      return idempotency_result(existing) if existing

      ServiceResult.failure(error: "high_risk_authorization_replayed")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private :authorize_under_permission_lock, :call_under_permission_lock

    private

    def with_fresh_authorized_actor
      permission = Commerce::HighRiskActionAuthorization.permission_for(@action)
      Identity::AuthorizedMutation.with(
        actor: @actor,
        all_of: permission,
        failure_code: "high_risk_unauthorized"
      ) do |actor|
        @actor = actor
        yield
      end
    end

    def validation_failure
      return ServiceResult.failure(error: "high_risk_action_invalid") unless ACTIONS.include?(@action)
      return ServiceResult.failure(error: "high_risk_target_invalid") unless @actor && @user && @membership_type
      return ServiceResult.failure(error: "high_risk_target_invalid") if @action == "membership.revoke" && !@membership
      return ServiceResult.failure(error: "high_risk_request_id_invalid") unless @request_id
      return ServiceResult.failure(error: "high_risk_reason_required") if @reason.blank?
      if @reason.length > Commerce::HighRiskActionAuthorization::MAX_REASON_LENGTH
        return ServiceResult.failure(error: "high_risk_reason_too_long")
      end

      permission = Commerce::HighRiskActionAuthorization.permission_for(@action)
      return ServiceResult.failure(error: "high_risk_unauthorized") unless @actor.permission?(permission)

      nil
    end

    def targets
      if @action == "membership.grant"
        [
          { type: "user", id: @user.public_id },
          { type: "membership_type", id: @membership_type.id }
        ]
      else
        [ { type: "membership", id: @membership.id, user_id: @user.public_id } ]
      end
    end

    def attributes
      if @action == "membership.grant"
        { grant_game_permissions: @grant_game_permissions }
      else
        { revoke_game_permissions: @revoke_game_permissions }
      end
    end

    def current_state
      if @action == "membership.grant"
        active = grant_window_memberships
          .order(:id)
          .map { |record| membership_state(record) }
        {
          user_id: @user.id,
          user_updated_at: @user.reload.updated_at,
          membership_type_id: @membership_type.id,
          membership_type_updated_at: @membership_type.reload.updated_at,
          active_memberships: active
        }
      else
        other_active = Commerce::UserMembership
          .currently_active
          .where(user: @user, store_membership_type_id: @membership_type.id)
          .where.not(id: @membership.id)
          .order(:id)
          .pluck(:id, :updated_at)
        membership_state(@membership.reload).merge(other_active_memberships: other_active)
      end
    end

    def membership_state(record)
      {
        membership_id: record.id,
        user_id: record.user_id,
        membership_type_id: record.store_membership_type_id,
        status: record.status,
        starts_at: record.starts_at,
        expires_at: record.expires_at,
        updated_at: record.updated_at
      }
    end

    def preview
      if @action == "membership.grant"
        latest_expiry = grant_window_memberships.maximum(:expires_at)
        starts_at = latest_expiry.present? && latest_expiry > Time.current ? latest_expiry : Time.current
        expires_at = @membership_type.permanent? ? nil : starts_at + @membership_type.duration_for_membership
        {
          action: @action,
          before: { active_membership_count: current_state[:active_memberships].size },
          after: {
            active_membership_count: current_state[:active_memberships].size + 1,
            starts_at: starts_at.iso8601,
            expires_at: expires_at&.iso8601,
            game_permissions_queued: @grant_game_permissions && @membership_type.game_permission_enabled?
          }
        }
      else
        {
          action: @action,
          before: membership_state(@membership),
          after: {
            membership_id: @membership.id,
            status: "revoked",
            game_permissions_queued: @revoke_game_permissions &&
              @membership_type.game_permission_enabled?
          }
        }
      end
    end

    def target_summary
      {
        username: @user.username,
        user_public_id: @user.public_id,
        membership_type: @membership_type.name,
        membership_id: @membership&.id
      }
    end

    def grant_window_memberships
      Commerce::UserMembership
        .active
        .where(user: @user, store_membership_type_id: @membership_type.id)
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
    end

    def lock_targets!
      @user.lock!
      @membership_type.lock!
      @membership&.lock!
    end

    def apply_action
      if @action == "membership.grant"
        result = Commerce::GrantMembership.call(
          user: @user,
          membership_type: @membership_type,
          source: "admin_grant",
          grant_game_permissions: @grant_game_permissions,
          idempotency_key: "high-risk:#{@request_id}:membership-grant"
        )
        return result if result.failure?

        ServiceResult.success(membership: result.value)
      else
        result = Commerce::RevokeMembership.call(
          membership: @membership,
          revoke_game_permissions: @revoke_game_permissions,
          idempotency_key: "high-risk:#{@request_id}:membership-revoke"
        )
        return result if result.failure?

        ServiceResult.success(membership: result.value[:membership])
      end
    end

    def request_fingerprint
      Commerce::HighRiskActionAuthorization.request_fingerprint(
        actor: @actor,
        action: @action,
        targets: targets,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      )
    end

    def idempotency_result(existing)
      return ServiceResult.failure(error: "high_risk_request_id_reused") unless existing
      unless secure_match?(existing.request_fingerprint, @request_fingerprint || request_fingerprint)
        return ServiceResult.failure(error: "high_risk_request_id_reused")
      end

      membership_id = existing.metadata["membership_id"] || existing.resource_id
      membership = Commerce::UserMembership.find_by(id: membership_id)
      return ServiceResult.failure(error: "high_risk_result_missing") unless membership

      ServiceResult.success(
        membership: membership,
        operation: existing,
        request_id: existing.request_id,
        idempotent: true
      )
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
