# frozen_string_literal: true

module Admin
  module Website
    class NavItemsController < BaseController
      before_action -> { require_permission("website.pages.read") }, only: %i[index]
      before_action -> { require_permission("website.pages.edit") }, except: %i[index]
      before_action :set_nav_item, only: %i[edit update destroy]

      def index
        items = ::Website::NavItem.order(:location, :position)

        render inertia: "Admin/Website/NavItems/Index", props: {
          title: t("mcweb.admin.website.nav.title", default: "Navigation"),
          items: items.map { |item| serialize_nav_item(item) },
          pages: ::Website::Page.order(:title).pluck(:public_id, :title, :slug).map { |id, title, slug| { id:, title:, slug: } },
          submitUrl: admin_website_nav_items_path,
          reorderUrl: reorder_admin_website_nav_items_path
        }
      end

      def create
        item = ::Website::NavItem.new(nav_item_params)
        item.position = (::Website::NavItem.where(location: item.location).maximum(:position) || -1) + 1

        if item.save
          redirect_to admin_website_nav_items_path, notice: t("mcweb.flash.created", resource: "Nav item")
        else
          redirect_to admin_website_nav_items_path, alert: item.errors.full_messages.to_sentence
        end
      end

      def update
        if @nav_item.update(nav_item_params)
          redirect_to admin_website_nav_items_path, notice: t("mcweb.flash.updated", resource: "Nav item")
        else
          redirect_to admin_website_nav_items_path, alert: @nav_item.errors.full_messages.to_sentence
        end
      end

      def destroy
        @nav_item.destroy!
        redirect_to admin_website_nav_items_path, notice: t("mcweb.flash.deleted", resource: "Nav item")
      end

      def reorder
        Array(params[:item_ids]).each_with_index do |id, index|
          ::Website::NavItem.find(id).update!(position: index)
        end
        head :ok
      end

      private

      def set_nav_item
        @nav_item = ::Website::NavItem.find(params[:id])
      end

      def nav_item_params
        permitted = params.require(:nav_item).permit(:label, :url, :website_page_id, :location, :visible, :position)
        resolve_page_public_id!(permitted)
        permitted[:url] = nil if permitted[:website_page_id].present?
        permitted
      end

      def resolve_page_public_id!(permitted)
        ref = permitted[:website_page_id]
        return if ref.blank?

        if ref.to_s.match?(/\A\d+\z/)
          permitted[:website_page_id] = ref.to_i
        else
          page = ::Website::Page.find_by!(public_id: ref)
          permitted[:website_page_id] = page.id
        end
      end

      def serialize_nav_item(item)
        {
          id: item.id,
          label: item.label,
          url: item.url,
          website_page_id: item.website_page_id,
          page_public_id: item.page&.public_id,
          location: item.location,
          visible: item.visible,
          position: item.position,
          href: item.href
        }
      end
    end
  end
end
