# frozen_string_literal: true

module Admin
  module Website
    class BlocksController < BaseController
      before_action -> { require_permission("website.pages.read") }
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_page
      before_action :set_block, only: %i[update destroy]

      def create
        result = ::Website::BlockMutation.call(
          page: @page, actor: current_user, action: :create,
          attributes: block_params, request_id: params[:request_id],
          expected_lock_version: params[:lock_version]
        )
        if result.success?
          redirect_to edit_admin_website_page_path(@page), notice: t("mcweb.flash.created", resource: t("mcweb.admin.website.blocks.resource"))
        else
          redirect_to edit_admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def update
        result = ::Website::BlockMutation.call(
          page: @page, actor: current_user, action: :update, block: @block,
          attributes: block_params, request_id: params[:request_id],
          expected_lock_version: params[:lock_version]
        )
        if result.success?
          redirect_to edit_admin_website_page_path(@page), notice: t("mcweb.flash.updated", resource: t("mcweb.admin.website.blocks.resource"))
        else
          redirect_to edit_admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def destroy
        result = ::Website::BlockMutation.call(
          page: @page, actor: current_user, action: :destroy, block: @block,
          request_id: params[:request_id], expected_lock_version: params[:lock_version]
        )
        if result.success?
          redirect_to edit_admin_website_page_path(@page), notice: t("mcweb.flash.deleted", resource: t("mcweb.admin.website.blocks.resource"))
        else
          redirect_to edit_admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def reorder
        result = ::Website::BlockMutation.call(
          page: @page, actor: current_user, action: :reorder,
          block_ids: params[:block_ids], request_id: params[:request_id],
          expected_lock_version: params[:lock_version]
        )
        if result.success?
          redirect_to edit_admin_website_page_path(@page)
        else
          redirect_to edit_admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      private

      def set_page
        @page = ::Website::Page.find_by!(public_id: params[:page_id])
      end

      def set_block
        @block = @page.blocks.find(params[:id])
      end

      def block_params
        permitted = params.require(:block).permit(:block_type, :position, :visible, settings: {})
        if permitted[:settings].is_a?(ActionController::Parameters)
          permitted[:settings] = permitted[:settings].to_unsafe_h
        end
        sanitize_block_settings!(permitted)
        permitted
      end

      def sanitize_block_settings!(permitted)
        settings = permitted[:settings]
        return unless settings.is_a?(Hash)

        if settings["cta_url"].present?
          settings["cta_url"] = ::Website::SafeLink.sanitize_href(settings["cta_url"])
        end
      end
    end
  end
end
