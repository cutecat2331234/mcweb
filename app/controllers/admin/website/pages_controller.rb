# frozen_string_literal: true

module Admin
  module Website
    class PagesController < BaseController
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_page, only: %i[show edit update destroy]

      def index
        pages = ::Website::Page.order(updated_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: "官网页面",
          columns: [
            admin_column(:title, "标题", link: true),
            admin_column(:slug, "标识"),
            admin_column(:status, "状态"),
            admin_column(:updated, "更新")
          ],
          rows: pages.map do |page|
            admin_row(
              title: page.title,
              slug: page.slug,
              status: page.status,
              updated: l(page.updated_at, format: :short),
              url: admin_website_page_path(page)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @page.title,
          subtitle: @page.slug,
          fields: [
            { label: "类型", value: @page.page_type },
            { label: "状态", value: @page.status },
            { label: "更新时间", value: l(@page.updated_at, format: :long) }
          ],
          backUrl: admin_website_pages_path
        }
      end

      def new
        @page = ::Website::Page.new
      end

      def create
        @page = ::Website::Page.new(page_params)

        if @page.save
          redirect_to admin_website_page_path(@page), notice: "Page created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @page.update(page_params)
          redirect_to admin_website_page_path(@page), notice: "Page updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @page.destroy!
        redirect_to admin_website_pages_path, notice: "Page deleted."
      end

      private

      def set_page
        @page = ::Website::Page.find_by!(public_id: params[:id])
      end

      def page_params
        params.expect(page: %i[title slug page_type status seo translations website_theme_id])[:page]
      end
    end
  end
end
