# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style custom BBCode management.
    class CustomBbcodesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_bbcode, only: %i[edit update destroy]

      def index
        codes = ::Community::CustomBbcode.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("custom_bbcodes.title"),
          subtitle: forum_t("custom_bbcodes.description"),
          columns: [
            admin_column(:tag, forum_t("custom_bbcodes.col_tag"), link: true),
            admin_column(:sample, forum_t("custom_bbcodes.col_sample")),
            admin_column(:active, forum_t("custom_bbcodes.col_active"))
          ],
          rows: codes.map do |code|
            admin_row(
              tag: "[#{code.tag}]",
              sample: code.sample.to_s,
              active: forum_yes_no(code.active),
              url: edit_admin_forum_custom_bbcode_path(code)
            )
          end,
          actions: [ { label: forum_t("custom_bbcodes.action_new"), href: new_admin_forum_custom_bbcode_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/CustomBbcodes/Form", props: form_props(::Community::CustomBbcode.new)
      end

      def create
        code = ::Community::CustomBbcode.new(bbcode_params)
        if code.save
          redirect_to admin_forum_custom_bbcodes_path, notice: t("mcweb.flash.custom_bbcode_created")
        else
          render inertia: "Admin/Forum/CustomBbcodes/Form", props: form_props(code), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/CustomBbcodes/Form", props: form_props(@bbcode, editing: true)
      end

      def update
        if @bbcode.update(bbcode_params)
          redirect_to admin_forum_custom_bbcodes_path, notice: t("mcweb.flash.custom_bbcode_updated")
        else
          render inertia: "Admin/Forum/CustomBbcodes/Form", props: form_props(@bbcode, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @bbcode.destroy!
        redirect_to admin_forum_custom_bbcodes_path, notice: t("mcweb.flash.custom_bbcode_deleted")
      end

      private

      def set_bbcode
        @bbcode = ::Community::CustomBbcode.find(params[:id])
      end

      def bbcode_params
        params.require(:custom_bbcode).permit(:tag, :replacement, :sample, :active)
      end

      def form_props(code, editing: false)
        {
          title: editing ? forum_t("custom_bbcodes.form_edit") : forum_t("custom_bbcodes.form_new"),
          custom_bbcode: {
            tag: code.tag || "",
            replacement: code.replacement || "",
            sample: code.sample || "",
            active: code.active.nil? ? true : code.active
          },
          submitUrl: editing ? admin_forum_custom_bbcode_path(code) : admin_forum_custom_bbcodes_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_custom_bbcodes_path,
          deleteUrl: editing ? admin_forum_custom_bbcode_path(code) : nil
        }
      end
    end
  end
end
