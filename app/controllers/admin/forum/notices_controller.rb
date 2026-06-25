# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style admin notices (dismissible banners).
    class NoticesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_notice, only: %i[edit update destroy]

      def index
        notices = ::Community::Notice.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("notices.title"),
          subtitle: forum_t("notices.description"),
          columns: [
            admin_column(:label, forum_t("notices.col_title"), link: true),
            admin_column(:style, forum_t("notices.col_style")),
            admin_column(:audience, forum_t("notices.col_audience")),
            admin_column(:active, forum_t("notices.col_active"))
          ],
          rows: notices.map do |notice|
            admin_row(
              label: notice.title,
              style: notice.style,
              audience: forum_t("notices.audience_#{notice.audience}"),
              active: forum_yes_no(notice.active),
              url: edit_admin_forum_notice_path(notice)
            )
          end,
          actions: [ { label: forum_t("notices.action_new"), href: new_admin_forum_notice_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Notices/Form", props: form_props(::Community::Notice.new)
      end

      def create
        notice = ::Community::Notice.new(notice_params)
        if notice.save
          redirect_to admin_forum_notices_path, notice: t("mcweb.flash.notice_created")
        else
          render inertia: "Admin/Forum/Notices/Form", props: form_props(notice), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Notices/Form", props: form_props(@notice, editing: true)
      end

      def update
        if @notice.update(notice_params)
          redirect_to admin_forum_notices_path, notice: t("mcweb.flash.notice_updated")
        else
          render inertia: "Admin/Forum/Notices/Form", props: form_props(@notice, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @notice.destroy!
        redirect_to admin_forum_notices_path, notice: t("mcweb.flash.notice_deleted")
      end

      private

      def set_notice
        @notice = ::Community::Notice.find(params[:id])
      end

      def notice_params
        params.require(:notice).permit(
          :title, :message, :style, :audience, :active, :dismissible,
          :min_trust_level, :max_trust_level, :position, :starts_at, :ends_at
        )
      end

      def form_props(notice, editing: false)
        {
          title: editing ? forum_t("notices.form_edit") : forum_t("notices.form_new"),
          notice: {
            title: notice.title || "",
            message: notice.message || "",
            style: notice.style || "info",
            audience: notice.audience || "everyone",
            active: notice.active.nil? ? true : notice.active,
            dismissible: notice.dismissible.nil? ? true : notice.dismissible,
            min_trust_level: notice.min_trust_level,
            max_trust_level: notice.max_trust_level,
            position: notice.position || 0,
            starts_at: notice.starts_at&.strftime("%Y-%m-%dT%H:%M"),
            ends_at: notice.ends_at&.strftime("%Y-%m-%dT%H:%M")
          },
          styleOptions: ::Community::Notice::STYLES.map { |s| { value: s, label: forum_t("notices.style_#{s}") } },
          audienceOptions: ::Community::Notice::AUDIENCES.map { |a| { value: a, label: forum_t("notices.audience_#{a}") } },
          submitUrl: editing ? admin_forum_notice_path(notice) : admin_forum_notices_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_notices_path,
          deleteUrl: editing ? admin_forum_notice_path(notice) : nil
        }
      end
    end
  end
end
