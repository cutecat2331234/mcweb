# frozen_string_literal: true

module Admin
  module Website
    class PagesController < BaseController
      before_action -> { require_permission("admin.website.manage") }
      before_action :set_page, only: %i[show edit update destroy]

      def index
        @pages = ::Website::Page.order(updated_at: :desc)
      end

      def show
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
