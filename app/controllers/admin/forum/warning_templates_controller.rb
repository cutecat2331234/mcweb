# frozen_string_literal: true

module Admin
  module Forum
    class WarningTemplatesController < BaseController
      before_action -> { require_permission("forum.users.warn") }
      before_action :set_template, only: %i[edit update destroy]

      def index
        templates = ::Community::WarningTemplate.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("warning_templates.title"),
          columns: [
            admin_column(:name, forum_t("warning_templates.col_name"), link: true),
            admin_column(:points, forum_t("warning_templates.col_points"))
          ],
          rows: templates.map do |template|
            admin_row(
              name: template.name,
              points: template.points,
              url: edit_admin_forum_warning_template_path(template)
            )
          end,
          actions: [ { label: forum_t("warning_templates.action_new"), href: new_admin_forum_warning_template_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/WarningTemplates/Form", props: form_props(::Community::WarningTemplate.new)
      end

      def create
        template = ::Community::WarningTemplate.new(template_params)
        if template.save
          redirect_to admin_forum_warning_templates_path, notice: t("mcweb.flash.warning_template_created")
        else
          render inertia: "Admin/Forum/WarningTemplates/Form", props: form_props(template), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/WarningTemplates/Form", props: form_props(@template, editing: true)
      end

      def update
        if @template.update(template_params)
          redirect_to admin_forum_warning_templates_path, notice: t("mcweb.flash.warning_template_updated")
        else
          render inertia: "Admin/Forum/WarningTemplates/Form", props: form_props(@template, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @template.destroy!
        redirect_to admin_forum_warning_templates_path, notice: t("mcweb.flash.warning_template_deleted")
      end

      private

      def set_template
        @template = ::Community::WarningTemplate.find(params[:id])
      end

      def template_params
        params.require(:warning_template).permit(:name, :reason, :points, :expire_days, :position)
      end

      def form_props(template, editing: false)
        {
          title: editing ? forum_t("warning_templates.form_edit") : forum_t("warning_templates.form_new"),
          warning_template: {
            name: template.name || "",
            reason: template.reason || "",
            points: template.points || 1,
            expire_days: template.expire_days
          },
          submitUrl: editing ? admin_forum_warning_template_path(template) : admin_forum_warning_templates_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_warning_templates_path,
          deleteUrl: editing ? admin_forum_warning_template_path(template) : nil
        }
      end
    end
  end
end
