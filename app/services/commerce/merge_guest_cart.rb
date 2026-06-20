# frozen_string_literal: true

module Commerce
  class MergeGuestCart < ApplicationService
    def initialize(user:, session_token:)
      @user = user
      @session_token = session_token
    end

    def call
      return ServiceResult.success(merged: false) if @session_token.blank?

      guest_cart = Commerce::Cart.find_by(session_token: @session_token)
      return ServiceResult.success(merged: false) unless guest_cart
      return ServiceResult.success(merged: false) if guest_cart.user_id.present?
      return ServiceResult.success(merged: false) if guest_cart.items.none?

      user_cart = Commerce::Cart.find_or_create_by!(user: @user)

      guest_cart.items.includes(:product, :variant).find_each do |item|
        validation = Commerce::ValidateCartItem.call(
          user: @user,
          product: item.product,
          variant: item.variant,
          quantity: item.quantity,
          cart: user_cart
        )
        return validation unless validation.success?
      end

      Commerce::Cart.transaction do
        guest_cart.items.find_each do |item|
          user_cart.add_item!(product: item.product, variant: item.variant, quantity: item.quantity)
        end
        guest_cart.items.destroy_all
        guest_cart.destroy!
      end

      ServiceResult.success(merged: true, cart: user_cart)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
