# frozen_string_literal: true

module GuestCartMergeable
  extend ActiveSupport::Concern

  private

  def merge_guest_cart!
    token = cookies.signed[:cart_token]
    return if token.blank?

    result = Commerce::MergeGuestCart.call(user: current_user, session_token: token)
    cookies.delete(:cart_token) if result.success? && result.value[:merged]
  end
end
