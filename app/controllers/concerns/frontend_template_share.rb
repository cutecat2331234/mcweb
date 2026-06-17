# frozen_string_literal: true

module FrontendTemplateShare
  extend ActiveSupport::Concern

  included do
    before_action :capture_template_preview
  end

  private

  def capture_template_preview
    return if admin_request?
    return if params[:preview_template].blank?
    return unless current_user&.permission?("website.templates.manage")

    session[:preview_template_key] = params[:preview_template].to_s
  end

  def admin_request?
    is_a?(Admin::BaseController) || request.path.start_with?("/admin")
  end

  def frontend_template_scope_for_request
    return nil if admin_request?

    case self.class.name
    when /\AWebsite::/ then "website"
    when /\ACommunity::/, /\ACommerce::/, /\AIdentity::/, /\APayments::/, /\AMinecraft::/ then "portal"
    end
  end

  def share_active_template
    scope = frontend_template_scope_for_request
    return {} unless scope

    result = Frontend::ResolveActiveTemplate.call(
      scope: scope,
      preview_key: session[:preview_template_key]
    )
    template = result.value
    return {} unless template

    serialized = Frontend::SerializeActiveTemplate.call(template: template, scope: scope).value
    { activeTemplate: serialized }
  end
end
