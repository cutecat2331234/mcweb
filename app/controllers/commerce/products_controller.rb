# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    layout "application"

    def index
      @pagy, @products = pagy(
        Commerce::Product.includes(:category).available.order(created_at: :desc),
        limit: 20
      )
    end

    def show
      @product = Commerce::Product.available.find_by!(public_id: params[:id])
    end
  end
end
