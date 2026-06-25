# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style user title ladder management.
    class UserTitlesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_rung, only: %i[edit update destroy]

      def index
        rungs = ::Community::UserTitleLadder.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("user_titles.title"),
          subtitle: forum_t("user_titles.description"),
          columns: [
            admin_column(:min_posts, forum_t("user_titles.col_min_posts")),
            admin_column(:label, forum_t("user_titles.col_title"), link: true)
          ],
          rows: rungs.map do |rung|
            admin_row(
              min_posts: rung.min_posts,
              label: rung.title,
              url: edit_admin_forum_user_title_path(rung)
            )
          end,
          actions: [ { label: forum_t("user_titles.action_new"), href: new_admin_forum_user_title_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/UserTitles/Form", props: form_props(::Community::UserTitleLadder.new)
      end

      def create
        rung = ::Community::UserTitleLadder.new(rung_params)
        if rung.save
          redirect_to admin_forum_user_titles_path, notice: t("mcweb.flash.user_title_created")
        else
          render inertia: "Admin/Forum/UserTitles/Form", props: form_props(rung), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/UserTitles/Form", props: form_props(@rung, editing: true)
      end

      def update
        if @rung.update(rung_params)
          redirect_to admin_forum_user_titles_path, notice: t("mcweb.flash.user_title_updated")
        else
          render inertia: "Admin/Forum/UserTitles/Form", props: form_props(@rung, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @rung.destroy!
        redirect_to admin_forum_user_titles_path, notice: t("mcweb.flash.user_title_deleted")
      end

      private

      def set_rung
        @rung = ::Community::UserTitleLadder.find(params[:id])
      end

      def rung_params
        params.require(:user_title).permit(:min_posts, :title)
      end

      def form_props(rung, editing: false)
        {
          title: editing ? forum_t("user_titles.form_edit") : forum_t("user_titles.form_new"),
          user_title: {
            min_posts: rung.min_posts || 0,
            title: rung.title || ""
          },
          submitUrl: editing ? admin_forum_user_title_path(rung) : admin_forum_user_titles_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_user_titles_path,
          deleteUrl: editing ? admin_forum_user_title_path(rung) : nil
        }
      end
    end
  end
end
