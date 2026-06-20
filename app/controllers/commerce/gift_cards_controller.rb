# frozen_string_literal: true

module Commerce
  class GiftCardsController < ApplicationController
    include Commerce::CodePreviewRateLimitable

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

      if card && gift_card_owner?(card)
        return render inertia: "Commerce/GiftCards/Show", props: {
          gift_card: serialize_gift_card_detail(card, for_owner: true),
          code: code,
          loggedIn: logged_in?,
          applyUrl: store_apply_gift_card_path(code: card.code)
        }
      end

      render inertia: "Commerce/GiftCards/Show", props: public_gift_card_props(code)
    end

    def apply
      return redirect_to identity_sign_in_path, alert: t("mcweb.flash.sign_in_required_short") unless logged_in?
      if apply_code_rate_limited?
        return redirect_to store_cart_path, alert: t("mcweb.flash.rate_limited", default: "操作过于频繁，请稍后再试。")
      end

      code = params[:code].to_s.strip.upcase
      card = Commerce::GiftCard.find_by(code: code)

      unless card&.redeemable?
        return redirect_to store_cart_path, alert: service_error_message(
          ServiceResult.failure(error: "gift_card_unavailable")
        )
      end

      claim = Commerce::ClaimGiftCard.call(user: current_user, gift_card: card)
      if claim.success?
        session[:pending_gift_card_code] = card.code
        redirect_to store_cart_path, notice: t("mcweb.flash.gift_card_updated")
      else
        redirect_to store_cart_path, alert: service_error_message(claim)
      end
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
      card && logged_in? && card.owner_user_id == current_user.id
    end

    def public_gift_card_props(code)
      {
        gift_card: {
          code: code,
          redeemable: false,
          status_label: t("mcweb.labels.gift_card_public_status.unavailable"),
          owned: false
        },
        code: code,
        loggedIn: logged_in?,
        applyUrl: logged_in? ? store_apply_gift_card_path(code: code) : nil
      }
    end

    def public_card_status_label(card)
      return t("mcweb.labels.gift_card_public_status.claimed") if card.owner_user_id.present?

      card.redeemable? ? t("mcweb.labels.gift_card_public_status.redeemable") : card_status_label(card)
    end

    def card_status_label(card)
      return t("mcweb.labels.gift_card_public_status.inactive") unless card.active?
      return t("mcweb.labels.gift_card_public_status.expired") if card.expired?
      return t("mcweb.labels.gift_card_public_status.zero_balance") unless card.balance_cents.positive?

      t("mcweb.labels.gift_card_public_status.available")
    end
  end
end
