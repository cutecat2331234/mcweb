# frozen_string_literal: true

module Identity
  class UpdateProfile < ApplicationService
    ATTRIBUTES = %i[display_name locale time_zone].freeze
    MANAGE_PERMISSION = "system.settings.manage"

    def initialize(actor:, user:, attributes:, ip_address: nil, user_agent: nil)
      @actor = actor
      @user = user
      @attributes = attributes.to_h.deep_symbolize_keys.slice(*ATTRIBUTES)
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("invalid_actor") unless @actor&.persisted? &&
        @actor.session_eligible?
      return failure("invalid_user") unless @user&.persisted?
      return failure("empty_attributes") if @attributes.empty?
      return failure("forbidden") unless allowed?

      normalize_attributes!
      changed = false
      changed_fields = []
      User.transaction do
        @user.lock!
        before_state = snapshot(@user)
        @user.assign_attributes(@attributes)
        changed_fields = @user.changes_to_save.keys & ATTRIBUTES.map(&:to_s)
        changed = changed_fields.any?
        @user.save! if changed
        if changed
          Administration::AuditLogger.call(
            actor: @actor,
            action: "identity.user.profile_updated",
            resource: @user,
            metadata: {
              changed_fields: changed_fields.sort
            },
            before_state:,
            after_state: snapshot(@user),
            ip_address: @ip_address,
            user_agent: @user_agent
          )
        end
      end

      ServiceResult.success(user: @user.reload, changed:)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(
        code: "validation_failed",
        errors: e.record.errors.to_hash
      )
    end

    private

    def allowed?
      return true if @actor.id == @user.id

      @actor.permission?(MANAGE_PERMISSION)
    end

    def normalize_attributes!
      if @attributes.key?(:display_name)
        @attributes[:display_name] = @attributes[:display_name].to_s.strip.presence
      end
      if @attributes.key?(:locale)
        raw_locale = @attributes[:locale].to_s.strip
        @attributes[:locale] = Mcweb::LocaleResolver.normalize(raw_locale) || raw_locale
      end
      @attributes[:time_zone] = @attributes[:time_zone].to_s.strip if @attributes.key?(:time_zone)
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
