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
        SiteSetting.set(setting_key, nil)
        log_audit(nil, "deactivated")
        return ServiceResult.success(nil)
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
