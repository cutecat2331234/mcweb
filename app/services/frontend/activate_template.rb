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
        return ServiceResult.failure(error: "无效的 scope")
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
      return ServiceResult.failure(error: "模板不存在或未安装") unless template
      return ServiceResult.failure(error: "模板不支持 #{@scope} 范围") unless template.supports_scope?(@scope)

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
