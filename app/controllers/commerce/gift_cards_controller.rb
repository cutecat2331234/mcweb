# frozen_string_literal: true

module Commerce
  class GiftCardsController < ApplicationController
    def show
      code = params[:code].to_s.strip.upcase
      card = Commerce::GiftCard.find_by(code: code)

      unless card
        return render inertia: "Commerce/GiftCards/Show", props: {
          gift_card: nil,
          code: code,
          loggedIn: logged_in?
        }
      end

      render inertia: "Commerce/GiftCards/Show", props: {
        gift_card: {
          code: card.code,
          balance_label: format_money(card.balance_cents, card.currency),
          initial_balance_label: format_money(card.initial_balance_cents, card.currency),
          expires_at: card.expires_at ? l(card.expires_at, format: :short) : nil,
          redeemable: card.redeemable?,
          status_label: card_status_label(card)
        },
        code: code,
        loggedIn: logged_in?,
        applyUrl: apply_store_gift_card_path(code: card.code)
      }
    end

    def apply
      require_login
      code = params[:code].to_s.strip.upcase
      card = Commerce::GiftCard.find_by(code: code)
      return redirect_to store_gift_card_path(code), alert: "礼品卡无效。" unless card
      return redirect_to store_gift_card_path(code), alert: card.inapplicable_reason if card.inapplicable_reason

      session[:pending_gift_card_code] = card.code
      redirect_to store_cart_path, notice: "礼品卡 #{card.code} 已保存，结账时自动使用。"
    end

    private

    def card_status_label(card)
      return "已停用" unless card.active?
      return "已过期" if card.expired?
      return "余额为零" unless card.balance_cents.positive?

      "可用"
    end
  end
end
