# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style custom page (node) management.
    class PagesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_page, only: %i[edit update destroy]

      def index
        pages = ::Community::ForumPage.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("pages.title"),
          subtitle: forum_t("pages.description"),
          columns: [
            admin_column(:title, forum_t("pages.col_title"), link: true),
            admin_column(:in_nav, forum_t("pages.col_nav")),
            admin_column(:published, forum_t("pages.col_published"))
          ],
          rows: pages.map do |page|
            admin_row(
              title: page.title,
              in_nav: forum_yes_no(page.show_in_nav),
              published: forum_yes_no(page.published),
              url: edit_admin_forum_page_path(page)
            )
          end,
          actions: [ { label: forum_t("pages.action_new"), href: new_admin_forum_page_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Pages/Form", props: form_props(::Community::ForumPage.new)
      end

      def create
        page = ::Community::ForumPage.new(page_params)
        if page.save
          redirect_to admin_forum_pages_path, notice: t("mcweb.flash.forum_page_created")
        else
          render inertia: "Admin/Forum/Pages/Form", props: form_props(page), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Pages/Form", props: form_props(@page, editing: true)
      end

      def update
        if @page.update(page_params)
          redirect_to admin_forum_pages_path, notice: t("mcweb.flash.forum_page_updated")
        else
          render inertia: "Admin/Forum/Pages/Form", props: form_props(@page, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @page.destroy!
        redirect_to admin_forum_pages_path, notice: t("mcweb.flash.forum_page_deleted")
      end

      private

      def set_page
        @page = ::Community::ForumPage.find(params[:id])
      end

      def page_params
        params.require(:forum_page).permit(:title, :slug, :body, :show_in_nav, :nav_label, :position, :published)
      end

      def form_props(page, editing: false)
        {
          title: editing ? forum_t("pages.form_edit") : forum_t("pages.form_new"),
          forum_page: {
            title: page.title || "",
            slug: page.slug || "",
            body: page.body || "",
            show_in_nav: page.show_in_nav.nil? ? false : page.show_in_nav,
            nav_label: page.nav_label || "",
            position: page.position || 0,
            published: page.published.nil? ? true : page.published
          },
          submitUrl: editing ? admin_forum_page_path(page) : admin_forum_pages_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_pages_path,
          deleteUrl: editing ? admin_forum_page_path(page) : nil
        }
      end
    end
  end
end
