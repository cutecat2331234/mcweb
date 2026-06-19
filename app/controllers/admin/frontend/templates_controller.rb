# frozen_string_literal: true

module Admin
  module Frontend
    class TemplatesController < BaseController
      before_action -> { require_permission("website.templates.manage") }
      before_action :set_template, only: %i[update destroy preview]
      before_action :ensure_builtin_template, only: :index

      def index
        render inertia: "Admin/Frontend/Templates/Index", props: {
        templates: ::Frontend::Template.order(created_at: :desc).map { |template| serialize_template(template) },
        activeWebsiteTemplate: ::Frontend::Template.active_key_for("website"),
        activePortalTemplate: ::Frontend::Template.active_key_for("portal"),
          uploadUrl: admin_frontend_templates_path,
          starterDownloadUrl: "/template-starter/starter.zip"
        }
      end

      def create
        file = params[:archive]
        return redirect_with_alert("请选择模板压缩包") unless file.respond_to?(:read)

        result = ::Frontend::InstallTemplateArchive.call(archive_io: file, actor: current_user)
        if result.success?
          redirect_to admin_frontend_templates_path, notice: "模板「#{result.value.name}」安装成功。"
        else
          redirect_to admin_frontend_templates_path, alert: result.error
        end
      end

      def update
        result = ::Frontend::ActivateTemplate.call(
          scope: params.require(:scope),
          template_key: params[:template_key],
          actor: current_user
        )
        if result.success?
          redirect_to admin_frontend_templates_path, notice: activation_notice
        else
          redirect_to admin_frontend_templates_path, alert: result.error
        end
      end

      def destroy
        result = ::Frontend::DeleteTemplate.call(template: @template, actor: current_user)
        if result.success?
          redirect_to admin_frontend_templates_path, notice: "模板已删除。"
        else
          redirect_to admin_frontend_templates_path, alert: result.error
        end
      end

      def preview
        scope = params[:scope].presence || @template.scopes.first
        target = scope == "portal" ? store_products_url : root_url
        redirect_to "#{target}?preview_template=#{@template.key}"
      end

      private

      def set_template
        @template = ::Frontend::Template.find(params[:id])
      end

      def serialize_template(template)
        {
          id: template.id,
          key: template.key,
          name: template.name,
          version: template.version,
          scopes: template.scopes,
          status: template.status,
          checksum: template.checksum,
          builtin: builtin_template?(template),
          error_message: template.error_message,
          update_url: admin_frontend_template_path(template),
          preview_website_url: template.supports_scope?("website") ? preview_admin_frontend_template_path(template, scope: "website") : nil,
          preview_portal_url: template.supports_scope?("portal") ? preview_admin_frontend_template_path(template, scope: "portal") : nil,
          delete_url: admin_frontend_template_path(template)
        }
      end

      def activation_notice
        if params[:template_key].present?
          "模板已激活。"
        else
          "模板已停用。"
        end
      end

      def redirect_with_alert(message)
        redirect_to admin_frontend_templates_path, alert: message
      end

      def ensure_builtin_template
        ::Frontend::EnsureDefaultTemplate.call
      end

      def builtin_template?(template)
        template.key == ::Frontend::EnsureDefaultTemplate::BUILTIN_KEY ||
          template.manifest.is_a?(Hash) && template.manifest["builtin"] == true
      end
    end
  end
end
