# frozen_string_literal: true

module Identity
  class UpdateProfile < ApplicationService
    ATTRIBUTES = %i[display_name locale time_zone].freeze
    MANAGE_PERMISSION = "system.settings.manage"

    def initialize(actor:, user:, attributes:)
      @actor = actor
      @user = user
      @attributes = attributes.to_h.deep_symbolize_keys.slice(*ATTRIBUTES)
    end

    def call
      return failure("invalid_actor") unless @actor&.persisted? &&
        @actor.session_eligible?
      return failure("invalid_user") unless @user&.persisted?
      return failure("empty_attributes") if @attributes.empty?
      return failure("forbidden") unless allowed?

      changed = false
      User.transaction do
        @user.lock!
        before_state = snapshot(@user)
        @user.assign_attributes(@attributes)
        changed = @user.changed?
        @user.save! if changed
        if changed
          Administration::AuditLogger.call(
            actor: @actor,
            action: "identity.user.profile_updated",
            resource: @user,
            metadata: {
              changed_fields: @attributes.keys.map(&:to_s).sort
            },
            before_state:,
            after_state: snapshot(@user)
          )
        end
      end

      ServiceResult.success(user: @user.reload, changed:)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(
        code: "validation_failed",
        error: "validation_failed",
        errors: e.record.errors.to_hash
      )
    end

    private

    def allowed?
      return true if @actor.id == @user.id

      @actor.permission?(MANAGE_PERMISSION)
    end

    def snapshot(user)
      {
        public_id: user.public_id,
        display_name: user.display_name,
        locale: user.locale,
        time_zone: user.time_zone
      }
    end

    def failure(code)
      ServiceResult.failure(code:, error: code)
    end
  end
end
