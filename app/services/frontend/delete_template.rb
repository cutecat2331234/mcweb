# frozen_string_literal: true

module Frontend
  class DeleteTemplate < ApplicationService
    def initialize(template:, actor: nil)
      @template = template
      @actor = actor
    end

    def call
      if builtin?
        return ServiceResult.failure(error: "内置默认模板无法删除。")
      end

      Frontend::Template::SITE_SETTING_KEYS.each do |scope, setting_key|
        SiteSetting.unset(setting_key) if SiteSetting.get(setting_key) == @template.key
      end

      path = @template.installed_path
      FileUtils.rm_rf(path) if path.present? && Pathname(path).exist?

      key = @template.key
      @template.destroy!

      log_audit(key)
      Frontend::EnsureDefaultTemplate.call
      ServiceResult.success(true)
    end

    private

    def builtin?
      @template.key == Frontend::EnsureDefaultTemplate::BUILTIN_KEY ||
        @template.manifest.is_a?(Hash) && @template.manifest["builtin"] == true
    end

    def log_audit(key)
      return unless @actor

      Administration::AuditLogger.call(
        actor: @actor,
        action: "frontend.template.deleted",
        metadata: { key: key }
      )
    end
  end
end
