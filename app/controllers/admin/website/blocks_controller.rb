# frozen_string_literal: true

module Admin
  module Website
    class BlocksController < BaseController
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_page
      before_action :set_block, only: %i[update destroy]

      def create
        block = @page.blocks.build(block_params)
        block.position = (@page.blocks.unscope(:order).maximum(:position) || -1) + 1

        if block.save
          redirect_to edit_admin_website_page_path(@page), notice: t("mcweb.flash.created", resource: "Block")
        else
          redirect_to edit_admin_website_page_path(@page), alert: block.errors.full_messages.to_sentence
        end
      end

      def update
        if @block.update(block_params)
          redirect_to edit_admin_website_page_path(@page), notice: t("mcweb.flash.updated", resource: "Block")
        else
          redirect_to edit_admin_website_page_path(@page), alert: @block.errors.full_messages.to_sentence
        end
      end

      def destroy
        @block.destroy!
        redirect_to edit_admin_website_page_path(@page), notice: t("mcweb.flash.deleted", resource: "Block")
      end

      def reorder
        ::Website::Block.transaction do
          Array(params[:block_ids]).each_with_index do |id, index|
            @page.blocks.find(id).update!(position: index)
          end
        end
        redirect_to edit_admin_website_page_path(@page)
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
