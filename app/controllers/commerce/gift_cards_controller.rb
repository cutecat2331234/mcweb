# frozen_string_literal: true

module Commerce
  class GiftCardsController < ApplicationController
    before_action :require_login, only: %i[index apply]

    def index
      cards = Commerce::GiftCard
        .where(owner_user_id: current_user.id)
        .order(updated_at: :desc)

      render inertia: "Commerce/GiftCards/Index", props: {
        gift_cards: cards.map { |card| serialize_wallet_card(card) }
      }
    end

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
          status_label: card_status_label(card),
          owned: logged_in? && card.owner_user_id == current_user&.id
        },
        code: code,
        loggedIn: logged_in?,
        applyUrl: apply_store_gift_card_path(code: card.code)
      }
    end

    def apply
      code = params[:code].to_s.strip.upcase
      card = Commerce::GiftCard.find_by(code: code)
      return redirect_to store_gift_card_path(code), alert: "礼品卡无效。" unless card

      claim = Commerce::ClaimGiftCard.call(user: current_user, gift_card: card)
      unless claim.success?
        return redirect_to store_gift_card_path(code), alert: service_error_message(claim)
      end

      session[:pending_gift_card_code] = card.code
      redirect_to store_cart_path, notice: "礼品卡 #{card.code} 已保存到您的钱包，结账时自动使用。"
    end

    private

    def serialize_wallet_card(card)
      {
        code: card.code,
        balance_label: format_money(card.balance_cents, card.currency),
        expires_at: card.expires_at ? l(card.expires_at, format: :short) : nil,
        redeemable: card.redeemable?,
        status_label: card_status_label(card),
        url: store_gift_card_path(code: card.code)
      }
    end

    def card_status_label(card)
      return "已停用" unless card.active?
      return "已过期" if card.expired?
      return "余额为零" unless card.balance_cents.positive?

      "可用"
    end
  end
end
