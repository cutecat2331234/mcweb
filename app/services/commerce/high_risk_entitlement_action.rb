# frozen_string_literal: true

module Commerce
  class HighRiskEntitlementAction < ApplicationService
    ACTIONS = %w[entitlement.grant entitlement.revoke].freeze

    class << self
      def authorize(**args)
        new(**args).authorize
      end
    end

    def initialize(actor:, action:, user: nil, product: nil, entitlement: nil,
                   request_id:, reason:, authorization_token: nil, confirmation: nil,
                   ip_address: nil, user_agent: nil)
      @actor = actor
      @action = action.to_s
      @entitlement = entitlement
      @user = user || entitlement&.user
      @product = product || entitlement&.product
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
          target: {
            username: @user.username,
            user_public_id: @user.public_id,
            product: @product.name,
            entitlement_id: @entitlement&.id
          }
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

      entitlement = nil
      operation = nil
      Commerce::HighRiskOperation.transaction(requires_new: true) do
        lock_targets!
        existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
        return idempotency_result(existing) if existing

        before_state = current_state
        unless Commerce::HighRiskActionAuthorization.valid?(
          @authorization_token,
          actor: @actor,
          action: @action,
          targets: targets,
          state: before_state,
          attributes: attributes,
          request_id: @request_id,
          reason: @reason
        )
          return ServiceResult.failure(error: "high_risk_authorization_invalid")
        end

        entitlement = apply_action!
        after_state = entitlement_state(entitlement.reload)
        operation = Commerce::HighRiskOperation.create!(
          actor: @actor,
          target_user: @user,
          action: @action,
          request_id: @request_id,
          request_fingerprint: @request_fingerprint,
          authorization_digest: Commerce::HighRiskActionAuthorization.authorization_digest(
            @authorization_token
          ),
          resource_type: entitlement.class.name,
          resource_id: entitlement.id,
          resource_public_id: entitlement.try(:public_id),
          reason: @reason,
          target_snapshot: targets,
          before_state: before_state,
          after_state: after_state,
          metadata: {
            entitlement_id: entitlement.id,
            product_id: @product.id,
            confirmation_method: "signed_typed_challenge",
            request_id: @request_id
          }
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.#{@action.tr('.', '_')}",
          resource: entitlement,
          metadata: {
            high_risk_operation_id: operation.id,
            request_id: @request_id,
            target_user_id: @user.id,
            product_id: @product.id,
            confirmation_method: "signed_typed_challenge"
          },
          before_state: before_state,
          after_state: after_state,
          ip_address: @ip_address,
          user_agent: @user_agent,
          reason: @reason
        )
      end

      ServiceResult.success(
        entitlement: entitlement,
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
      return ServiceResult.failure(error: "high_risk_target_invalid") unless @actor && @user && @product
      return ServiceResult.failure(error: "high_risk_target_invalid") if @action == "entitlement.revoke" && !@entitlement
      if @action == "entitlement.grant" && entitlement_duration.blank?
        return ServiceResult.failure(error: "entitlement_not_configured")
      end
      return ServiceResult.failure(error: "high_risk_request_id_invalid") unless @request_id
      return ServiceResult.failure(error: "high_risk_reason_required") if @reason.blank?
      if @reason.length > Commerce::HighRiskActionAuthorization::MAX_REASON_LENGTH
        return ServiceResult.failure(error: "high_risk_reason_too_long")
      end

      permission = Commerce::HighRiskActionAuthorization.permission_for(@action)
      return ServiceResult.failure(error: "high_risk_unauthorized") unless @actor.permission?(permission)

      nil
    end

    def entitlement_duration
      config = @product.fulfillment_config.to_h.with_indifferent_access
      permanent = ActiveModel::Type::Boolean.new.cast(config[:entitlement_permanent])
      days = Integer(config[:entitlement_days].to_s, 10, exception: false).to_i
      return { permanent: true, days: nil } if permanent
      return { permanent: false, days: days } if days.positive?

      nil
    end

    def targets
      if @action == "entitlement.grant"
        [
          { type: "user", id: @user.public_id },
          { type: "product", id: @product.public_id }
        ]
      else
        [ { type: "entitlement", id: @entitlement.id, user_id: @user.public_id } ]
      end
    end

    def attributes
      { entitlement_duration: entitlement_duration }
    end

    def current_state
      if @action == "entitlement.grant"
        active = Commerce::UserEntitlement
          .currently_active
          .where(user: @user, store_product_id: @product.id)
          .order(:id)
          .map { |record| entitlement_state(record) }
        {
          user_id: @user.id,
          user_updated_at: @user.reload.updated_at,
          product_id: @product.id,
          product_updated_at: @product.reload.updated_at,
          active_entitlements: active
        }
      else
        entitlement_state(@entitlement.reload)
      end
    end

    def entitlement_state(record)
      {
        entitlement_id: record.id,
        user_id: record.user_id,
        product_id: record.store_product_id,
        starts_at: record.starts_at,
        expires_at: record.expires_at,
        revoked_at: record.revoked_at,
        updated_at: record.updated_at
      }
    end

    def preview
      if @action == "entitlement.grant"
        duration = entitlement_duration
        expires_at = duration[:permanent] ? nil : duration[:days].days.from_now
        {
          action: @action,
          before: { active_entitlement_count: current_state[:active_entitlements].size },
          after: {
            active_entitlement_count: current_state[:active_entitlements].size + 1,
            permanent: duration[:permanent],
            expires_at: expires_at&.iso8601
          }
        }
      else
        {
          action: @action,
          before: entitlement_state(@entitlement),
          after: { entitlement_id: @entitlement.id, revoked: true }
        }
      end
    end

    def lock_targets!
      @user.lock!
      @product.lock!
      @entitlement&.lock!
    end

    def apply_action!
      if @action == "entitlement.grant"
        duration = entitlement_duration
        starts_at = Time.current
        Commerce::UserEntitlement.create!(
          user: @user,
          product: @product,
          starts_at: starts_at,
          expires_at: duration[:permanent] ? nil : starts_at + duration[:days].days
        )
      else
        @entitlement.update!(revoked_at: Time.current) unless @entitlement.revoked_at?
        @entitlement
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

      entitlement_id = existing.metadata["entitlement_id"] || existing.resource_id
      entitlement = Commerce::UserEntitlement.find_by(id: entitlement_id)
      return ServiceResult.failure(error: "high_risk_result_missing") unless entitlement

      ServiceResult.success(
        entitlement: entitlement,
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
