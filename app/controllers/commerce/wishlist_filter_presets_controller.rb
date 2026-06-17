# frozen_string_literal: true

module Commerce
  class WishlistFilterPresetsController < ApplicationController
    before_action :require_login

    def index
      presets = current_user.store_wishlist_filter_presets.recent.limit(20)
      render json: presets.map { |preset| serialize_preset(preset) }
    end

    def create
      preset = current_user.store_wishlist_filter_presets.build(preset_params)
      if preset.save
        render json: serialize_preset(preset), status: :created
      else
        render json: { error: preset.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    def destroy
      preset = current_user.store_wishlist_filter_presets.find(params[:id])
      preset.destroy!
      head :no_content
    end

    private

    def preset_params
      params.require(:wishlist_filter_preset).permit(:name, filters: {})
    end

    def serialize_preset(preset)
      share_token = Commerce::EnsureWishlistShareToken.call(user: current_user).value&.dig(:token)
      query = wishlist_url_params(preset)

      {
        id: preset.id,
        name: preset.name,
        filters: preset.filters,
        url: store_wishlist_path(query),
        public_share_url: share_token ? store_public_wishlist_url(share_token, query) : nil,
        delete_url: store_wishlist_filter_preset_path(preset)
      }
    end

    def wishlist_url_params(preset)
      filters = preset.filters.symbolize_keys
      {
        in_stock: truthy?(filters[:in_stock]) ? "1" : nil,
        on_sale: truthy?(filters[:on_sale]) ? "1" : nil,
        coming_soon: truthy?(filters[:coming_soon]) ? "1" : nil,
        sort: filters[:sort].presence
      }.compact
    end

    def truthy?(value)
      value == true || value == "1" || value == "true"
    end
  end
end
