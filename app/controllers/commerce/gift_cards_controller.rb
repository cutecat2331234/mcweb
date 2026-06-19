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
        gift_card: serialize_gift_card_detail(card, for_owner: gift_card_owner?(card)),
        code: code,
        loggedIn: logged_in?,
        applyUrl: store_apply_gift_card_path(code: card.code)
      }
    end

    def apply
      code = params[:code].to_s.strip.upcase
      card = Commerce::GiftCard.find_by(code: code)
      return redirect_to store_gift_card_path(code), alert: t("mcweb.flash.gift_card_invalid") unless card

      claim = Commerce::ClaimGiftCard.call(user: current_user, gift_card: card)
      unless claim.success?
        return redirect_to store_gift_card_path(code), alert: service_error_message(claim)
      end

      session[:pending_gift_card_code] = card.code
      redirect_to store_cart_path, notice: t("mcweb.flash.gift_card_saved", code: card.code)
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

    def serialize_gift_card_detail(card, for_owner:)
      detail = {
        code: card.code,
        redeemable: card.redeemable?,
        status_label: for_owner ? card_status_label(card) : public_card_status_label(card),
        owned: for_owner
      }
      return detail unless for_owner

      detail.merge(
        balance_label: format_money(card.balance_cents, card.currency),
        initial_balance_label: format_money(card.initial_balance_cents, card.currency),
        expires_at: card.expires_at ? l(card.expires_at, format: :short) : nil
      )
    end

    def gift_card_owner?(card)
      logged_in? && card.owner_user_id == current_user.id
    end

    def public_card_status_label(card)
      return "已绑定" if card.owner_user_id.present?

      card.redeemable? ? "可领取" : card_status_label(card)
    end

    def card_status_label(card)
      return "已停用" unless card.active?
      return "已过期" if card.expired?
      return "余额为零" unless card.balance_cents.positive?

      "可用"
    end
  end
end
