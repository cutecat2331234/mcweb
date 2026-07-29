# frozen_string_literal: true

module Frontend
  class ActivateTemplate < ApplicationService
    def initialize(scope:, template_key:, actor: nil)
      @scope = scope.to_s
      @template_key = template_key
      @actor = actor
    end

    def call
      unless Frontend::Template::SCOPES.include?(@scope)
        return ServiceResult.failure(error: :invalid_template_scope)
      end

      setting_key = Frontend::Template::SITE_SETTING_KEYS.fetch(@scope)

      if @template_key.blank?
        SiteSetting.unset(setting_key)
        ::Frontend::EnsureDefaultTemplate.call
        builtin = ::Frontend::Template.installed.find_by(key: ::Frontend::EnsureDefaultTemplate::BUILTIN_KEY)
        if builtin&.supports_scope?(@scope)
          SiteSetting.set(setting_key, builtin.key)
          log_audit(builtin, "activated")
        else
          log_audit(nil, "deactivated")
        end
        return ServiceResult.success(builtin)
      end

      template = Frontend::Template.installed.find_by(key: @template_key)
      return ServiceResult.failure(error: :template_missing_or_not_installed) unless template
      unless template.supports_scope?(@scope)
        return ServiceResult.failure(
          error: I18n.t("mcweb.user_copy.template_scope_unsupported", scope: @scope)
        )
      end

      SiteSetting.set(setting_key, template.key)
      log_audit(template, "activated")
      ServiceResult.success(template)
    end

    private

    def log_audit(template, action)
      return unless @actor

      Administration::AuditLogger.call(
        actor: @actor,
        action: "frontend.template.#{action}",
        resource: template,
        metadata: { scope: @scope, key: template&.key }
      )
    end
  end
end
