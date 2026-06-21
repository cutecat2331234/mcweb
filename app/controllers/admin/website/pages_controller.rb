# frozen_string_literal: true

module Admin
  module Website
    class PagesController < BaseController
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_page, only: %i[show edit update destroy]

      def index
        pages = ::Website::Page.order(updated_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.website.pages.title"),
          columns: [
            admin_column(:title, t("mcweb.admin.website.pages.col_title"), link: true),
            admin_column(:slug, t("mcweb.admin.website.pages.col_slug")),
            admin_column(:status, t("mcweb.admin.common.status")),
            admin_column(:updated, t("mcweb.admin.common.updated"))
          ],
          rows: pages.map do |page|
            admin_row(
              title: page.title,
              slug: page.slug,
              status: page.status,
              updated: l(page.updated_at, format: :short),
              url: admin_website_page_path(page)
            )
          end,
          actions: [ { label: t("mcweb.admin.website.pages.new"), href: new_admin_website_page_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @page.title,
          subtitle: @page.slug,
          fields: [
            { label: t("mcweb.admin.website.pages.field_type"), value: @page.page_type },
            { label: t("mcweb.admin.common.status"), value: @page.status },
            { label: t("mcweb.admin.common.updated"), value: l(@page.updated_at, format: :long) }
          ],
          backUrl: admin_website_pages_path,
          actions: [ { label: t("mcweb.admin.ui.edit"), href: edit_admin_website_page_path(@page) } ]
        }
      end

      def new
        render inertia: "Admin/Website/Pages/Form", props: form_props(::Website::Page.new)
      end

      def create
        page = ::Website::Page.new(page_params)
        page.author = current_user

        if page.save
          redirect_to admin_website_page_path(page), notice: t("mcweb.flash.created", resource: t("mcweb.resources.page"))
        else
          render inertia: "Admin/Website/Pages/Form", props: form_props(page), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Website/Pages/Form", props: form_props(@page)
      end

      def update
        if @page.update(page_params)
          redirect_to admin_website_page_path(@page), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.page"))
        else
          render inertia: "Admin/Website/Pages/Form", props: form_props(@page), status: :unprocessable_entity
        end
      end

      def destroy
        @page.destroy!
        redirect_to admin_website_pages_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.page"))
      end

      private

      def set_page
        @page = ::Website::Page.find_by!(public_id: params[:id])
      end

      def page_params
        params.expect(page: %i[title slug page_type status])[:page]
      end

      def form_props(page)
        {
          title: page.persisted? ? t("mcweb.admin.website.pages.edit") : t("mcweb.admin.website.pages.new"),
          page: {
            title: page.title,
            slug: page.slug,
            page_type: page.page_type.presence || "custom",
            status: page.status.presence || "draft"
          },
          pageTypeOptions: %w[custom home landing].map { |value| { value:, label: value } },
          statusOptions: ::Website::Page.statuses.keys.map { |value| { value:, label: value } },
          submitUrl: page.persisted? ? admin_website_page_path(page) : admin_website_pages_path,
          method: page.persisted? ? "patch" : "post",
          backUrl: page.persisted? ? admin_website_page_path(page) : admin_website_pages_path,
          form_errors: page.errors.to_hash(true)
        }
      end
    end
  end
end
