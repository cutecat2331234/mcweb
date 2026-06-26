# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style smilie management (text code -> emoji substitution).
    class SmiliesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_smilie, only: %i[edit update destroy]

      def index
        smilies = ::Community::Smilie.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("smilies.title"),
          subtitle: forum_t("smilies.description"),
          columns: [
            admin_column(:code, forum_t("smilies.col_code"), link: true),
            admin_column(:emoji, forum_t("smilies.col_emoji")),
            admin_column(:smilie_title, forum_t("smilies.col_title")),
            admin_column(:active, forum_t("smilies.col_active"))
          ],
          rows: smilies.map do |smilie|
            admin_row(
              code: smilie.code,
              emoji: smilie.emoji,
              smilie_title: smilie.title.to_s,
              active: forum_yes_no(smilie.active),
              url: edit_admin_forum_smily_path(smilie)
            )
          end,
          actions: [ { label: forum_t("smilies.action_new"), href: new_admin_forum_smily_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Smilies/Form", props: form_props(::Community::Smilie.new)
      end

      def create
        smilie = ::Community::Smilie.new(smilie_params)
        if smilie.save
          redirect_to admin_forum_smilies_path, notice: t("mcweb.flash.smilie_created")
        else
          render inertia: "Admin/Forum/Smilies/Form", props: form_props(smilie), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Smilies/Form", props: form_props(@smilie, editing: true)
      end

      def update
        if @smilie.update(smilie_params)
          redirect_to admin_forum_smilies_path, notice: t("mcweb.flash.smilie_updated")
        else
          render inertia: "Admin/Forum/Smilies/Form", props: form_props(@smilie, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @smilie.destroy!
        redirect_to admin_forum_smilies_path, notice: t("mcweb.flash.smilie_deleted")
      end

      private

      def set_smilie
        @smilie = ::Community::Smilie.find(params[:id])
      end

      def smilie_params
        params.require(:smilie).permit(:code, :emoji, :title, :position, :active)
      end

      def form_props(smilie, editing: false)
        {
          title: editing ? forum_t("smilies.form_edit") : forum_t("smilies.form_new"),
          smilie: {
            code: smilie.code || "",
            emoji: smilie.emoji || "",
            title: smilie.title || "",
            position: smilie.position || 0,
            active: smilie.active.nil? ? true : smilie.active
          },
          submitUrl: editing ? admin_forum_smily_path(smilie) : admin_forum_smilies_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_smilies_path,
          deleteUrl: editing ? admin_forum_smily_path(smilie) : nil
        }
      end
    end
  end
end
