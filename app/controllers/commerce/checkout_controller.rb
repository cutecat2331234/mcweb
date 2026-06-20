# frozen_string_literal: true

module Commerce
  class CheckoutController < ApplicationController
    include Commerce::CodePreviewRateLimitable

    before_action :require_login

    def show
      cart = Commerce::Cart.find_by(user: current_user)
      items = cart&.items&.includes(:product, :variant) || []
      providers = Payments::ProviderConfig.enabled_providers.map { |config| serialize_checkout_provider(config) }
      currency = items.first&.product&.currency || "CNY"
      subtotal_cents = cart&.subtotal_cents.to_i
      pending_coupon = apply_coupon_from_url!(items) if params[:coupon].present?
      pending_coupon ||= session[:pending_coupon_code].to_s.presence
      pending_gift_card = session[:pending_gift_card_code].to_s.presence
      coupon = Commerce::Coupon.find_by(code: pending_coupon) if pending_coupon.present?
      min_checkout_cents = SiteSetting.get("store.min_checkout_subtotal_cents", "0").to_i
      store_credit_balance = current_user.available_store_credit_cents
      shipping_enabled = Commerce::StoreFeatures.enabled?(:shipping)
      gift_wrap_enabled = Commerce::StoreFeatures.enabled?(:gift_wrap)

      props = {
        items: items.map { |item|
          {
            product_name: item.product.name,
            variant_name: item.variant&.name,
            quantity: item.quantity,
            total_label: format_money(item.total_cents, item.product.currency)
          }
        },
        subtotalCents: subtotal_cents,
        subtotalLabel: format_money(subtotal_cents, currency),
        pendingCouponCode: pending_coupon,
        pendingGiftCardCode: pending_gift_card,
        couponAutoApplied: params[:coupon].present? && pending_coupon.present?,
        providers: providers,
        defaultProvider: providers.first&.dig(:value),
        previewCouponUrl: preview_coupon_store_checkout_path,
        previewGiftCardUrl: preview_gift_card_store_checkout_path,
        minCheckoutCents: min_checkout_cents,
        minCheckoutLabel: min_checkout_cents.positive? ? format_money(min_checkout_cents, currency) : nil,
        belowMinCheckout: min_checkout_cents.positive? && subtotal_cents < min_checkout_cents,
        storeCreditBalanceCents: store_credit_balance,
        storeCreditBalanceLabel: store_credit_balance.positive? ? format_money(store_credit_balance, currency) : nil,
        previewStoreCreditUrl: preview_store_credit_store_checkout_path
      }

      if shipping_enabled
        requires_shipping = items.any? { |item| item.product&.requires_shipping? || item.product&.product_type == "physical" }
        props.merge!(
          requiresShipping: requires_shipping,
          defaultShippingAddress: default_shipping_address_for(current_user),
          savedAddresses: current_user.shipping_addresses.ordered.map { |address| serialize_saved_address(address) },
          shippingAddressesUrl: store_shipping_addresses_path,
          **serialize_shipping_quote(subtotal_cents, currency: currency, cart_items: items, coupon: coupon, shipping_method_code: params[:shipping_method])
        )
      end

      if gift_wrap_enabled
        gift_wrap_cents = SiteSetting.get("store.gift_wrap_cents", "500").to_i
        requires_shipping = items.any? { |item| item.product&.requires_shipping? || item.product&.product_type == "physical" }
        props.merge!(
          giftWrapAvailable: requires_shipping && gift_wrap_cents.positive?,
          giftWrapCents: gift_wrap_cents,
          giftWrapLabel: format_money(gift_wrap_cents, currency)
        )
      end

      render inertia: "Commerce/Checkout/Show", props: props
    end

    def create
      order = nil

      if params[:order_id].blank?
        cart = Commerce::Cart.find_by(user: current_user)
        if cart.nil? || cart.empty?
          return redirect_to store_cart_path, alert: t("mcweb.services.errors.cart_empty")
        end

        order_result = Commerce::CreateOrder.call(
          cart: cart,
          user: current_user,
          coupon_code: session.delete(:pending_coupon_code),
          gift_card_code: session.delete(:pending_gift_card_code),
          use_store_credit: checkout_params[:use_store_credit],
          notes: checkout_params[:notes],
          shipping_address: shipping_address_params,
          shipping_method: checkout_params[:shipping_method],
          gift_wrap: checkout_params[:gift_wrap]
        )
        unless order_result.success?
          return redirect_to store_checkout_path, alert: service_error_message(order_result)
        end

        order = order_result.value
      else
        order = Commerce::Order.find_by!(public_id: params[:order_id], user: current_user)
        unless order.payable?
          message = order.payment_expired? ? t("mcweb.services.errors.order_payment_expired") : t("mcweb.services.errors.order_cannot_continue_payment")
          return redirect_to store_order_path(order), alert: message
        end
      end

      if order.total_cents.zero?
        payment_record = resolve_pending_payment(order: order, provider: "fake", amount_cents: 0)
        result = Commerce::ConfirmPayment.call(
          payment_record: payment_record,
          provider_payment_id: "free-#{order.public_id}"
        )
        unless result.success?
          return redirect_to store_order_path(order), alert: service_error_message(result)
        end
        return redirect_to store_order_path(order), notice: t("mcweb.flash.order_confirmed")
      end

      provider_name = checkout_params[:provider].presence || default_provider

      begin_result = Commerce::BeginOrderPayment.call(order: order)
      unless begin_result.success?
        return redirect_to store_order_path(order), alert: service_error_message(begin_result)
      end
      order = begin_result.value

      payment_record = resolve_pending_payment(
        order: order,
        provider: provider_name,
        amount_cents: order.total_cents
      )

      result = Payments::Provider.for(provider_name).create_payment(payment_record)

      if result.success?
        redirect_to result.value[:checkout_url], allow_other_host: true
      else
        redirect_to store_order_path(order), alert: service_error_message(result)
      end
    rescue Payments::Provider::UnknownProviderError
      redirect_to checkout_redirect_path(order), alert: t("mcweb.flash.payment_method_unavailable")
    rescue ActiveRecord::RecordInvalid => e
      redirect_to checkout_redirect_path(order), alert: e.record.errors.full_messages.to_sentence
    end

    def preview_coupon
      return render_preview_rate_limited if preview_rate_limited?

      cart = Commerce::Cart.find_by(user: current_user)
      subtotal_cents = cart&.subtotal_cents.to_i
      cart_items = cart&.items&.includes(:product) || []
      currency = cart_items.first&.product&.currency || "CNY"
      result = Commerce::PreviewCoupon.call(
        subtotal_cents: subtotal_cents,
        code: params[:code],
        cart_items: cart_items,
        user: current_user,
        gift_wrap_cents: gift_wrap_cents_for_preview
      )

      if result.success?
        session[:pending_coupon_code] = result.value[:code]
        shipping_cents = result.value[:shipping_cents].to_i
        render json: {
          code: result.value[:code],
          discount_cents: result.value[:discount_cents],
          total_cents: result.value[:total_cents],
          discount_label: format_money(result.value[:discount_cents], currency),
          total_label: format_money(result.value[:total_cents], currency),
          shipping_label: format_money(shipping_cents, currency),
          free_shipping: result.value[:free_shipping],
          min_amount_label: result.value[:min_amount_label],
          amount_remaining_label: result.value[:amount_remaining_label]
        }
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def preview_gift_card
      return render_preview_rate_limited if preview_rate_limited?

      cart = Commerce::Cart.find_by(user: current_user)
      subtotal_cents = cart&.subtotal_cents.to_i
      discount_cents = 0
      cart_items = cart&.items&.includes(:product) || []
      if session[:pending_coupon_code].present?
        preview = Commerce::PreviewCoupon.call(
          subtotal_cents: subtotal_cents,
          code: session[:pending_coupon_code],
          cart_items: cart_items,
          user: current_user,
          gift_wrap_cents: gift_wrap_cents_for_preview
        )
        discount_cents = preview.success? ? preview.value[:discount_cents] : 0
        shipping_cents = preview.success? ? preview.value[:shipping_cents].to_i : shipping_cents_for_preview(subtotal_cents)
      else
        shipping_cents = shipping_cents_for_preview(subtotal_cents)
      end

      result = Commerce::PreviewGiftCard.call(
        subtotal_cents: subtotal_cents,
        code: params[:code],
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        gift_wrap_cents: gift_wrap_cents_for_preview
      )

      if result.success?
        session[:pending_gift_card_code] = result.value[:code]
        currency = cart&.items&.first&.product&.currency || "CNY"
        render json: {
          code: result.value[:code],
          gift_card_amount_cents: result.value[:gift_card_amount_cents],
          total_cents: result.value[:total_cents],
          gift_card_amount_label: format_money(result.value[:gift_card_amount_cents], currency),
          total_label: format_money(result.value[:total_cents], currency)
        }
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def preview_store_credit
      return render_preview_rate_limited if preview_rate_limited?

      cart = Commerce::Cart.find_by(user: current_user)
      subtotal_cents = cart&.subtotal_cents.to_i
      cart_items = cart&.items&.includes(:product) || []
      currency = cart_items.first&.product&.currency || "CNY"
      discount_cents = 0
      shipping_cents = shipping_cents_for_preview(subtotal_cents)
      gift_card_amount_cents = 0

      if session[:pending_coupon_code].present?
        preview = Commerce::PreviewCoupon.call(
          subtotal_cents: subtotal_cents,
          code: session[:pending_coupon_code],
          cart_items: cart_items,
          user: current_user,
          gift_wrap_cents: gift_wrap_cents_for_preview
        )
        if preview.success?
          discount_cents = preview.value[:discount_cents]
          shipping_cents = preview.value[:shipping_cents].to_i
        end
      end

      if session[:pending_gift_card_code].present?
        gift_preview = Commerce::PreviewGiftCard.call(
          subtotal_cents: subtotal_cents,
          code: session[:pending_gift_card_code],
          discount_cents: discount_cents,
          shipping_cents: shipping_cents,
          gift_wrap_cents: gift_wrap_cents_for_preview
        )
        gift_card_amount_cents = gift_preview.success? ? gift_preview.value[:gift_card_amount_cents] : 0
      end

      result = Commerce::PreviewStoreCredit.call(
        user: current_user,
        subtotal_cents: subtotal_cents,
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        gift_wrap_cents: gift_wrap_cents_for_preview,
        gift_card_amount_cents: gift_card_amount_cents
      )

      if result.success?
        render json: {
          balance_cents: result.value[:balance_cents],
          store_credit_amount_cents: result.value[:store_credit_amount_cents],
          total_cents: result.value[:total_cents],
          balance_label: format_money(result.value[:balance_cents], currency),
          store_credit_amount_label: format_money(result.value[:store_credit_amount_cents], currency),
          total_label: format_money(result.value[:total_cents], currency)
        }
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    private

    def checkout_params
      params.fetch(:checkout, {}).permit(:provider, :coupon_code, :gift_card_code, :notes, :shipping_method, :gift_wrap, :use_store_credit)
    end

    def shipping_address_params
      raw = params.fetch(:checkout, {}).fetch(:shipping_address, {}).permit(
        :name, :phone, :line1, :line2, :city, :province, :postal_code
      )
      raw.to_h
    end

    def last_shipping_address_for(user)
      saved = user.shipping_addresses.find_by(default_address: true) || user.shipping_addresses.ordered.first
      return saved.to_address_hash if saved

      order = Commerce::Order.where(user: user)
        .where.not(shipping_address: [ nil, {} ])
        .where.not(status: %w[cancelled failed pending awaiting_payment])
        .order(created_at: :desc)
        .first
      return nil unless order

      address = order.shipping_address
      return nil unless address.is_a?(Hash) && address.values.any?(&:present?)

      {
        name: address["name"].to_s,
        phone: address["phone"].to_s,
        line1: address["line1"].to_s,
        line2: address["line2"].to_s,
        city: address["city"].to_s,
        province: address["province"].to_s,
        postal_code: address["postal_code"].to_s
      }
    end

    def default_shipping_address_for(user)
      hash = last_shipping_address_for(user)
      return nil unless hash.is_a?(Hash) && hash.values.any?(&:present?)

      normalized = hash.with_indifferent_access
      {
        name: normalized[:name].to_s,
        phone: normalized[:phone].to_s,
        line1: normalized[:line1].to_s,
        line2: normalized[:line2].to_s,
        city: normalized[:city].to_s,
        province: normalized[:province].to_s,
        postal_code: normalized[:postal_code].to_s
      }
    end

    def serialize_saved_address(address)
      {
        id: address.id,
        label: address.label,
        summary: address.summary_label,
        address: address.to_address_hash
      }
    end

    def default_provider
      Payments::ProviderConfig.enabled_providers.pick(:provider) || "fake"
    end

    def gift_wrap_cents_for_preview
      return 0 unless Commerce::StoreFeatures.enabled?(:gift_wrap)
      return 0 unless ActiveModel::Type::Boolean.new.cast(params[:gift_wrap])

      SiteSetting.get("store.gift_wrap_cents", "500").to_i
    end

    def shipping_cents_for_preview(subtotal_cents, shipping_method_code: nil)
      cart = Commerce::Cart.find_by(user: current_user)
      cart_items = cart&.items&.includes(:product) || []
      coupon = Commerce::Coupon.find_by(code: session[:pending_coupon_code]) if session[:pending_coupon_code].present?
      result = Commerce::CalculateShipping.call(
        subtotal_cents: subtotal_cents,
        cart_items: cart_items,
        coupon: coupon,
        shipping_method_code: shipping_method_code || params[:shipping_method]
      )
      result.success? ? result.value[:shipping_cents].to_i : 0
    end

    def apply_coupon_from_url!(cart_items)
      code = params[:coupon].to_s.strip
      return nil if code.blank?
      return nil if preview_rate_limited?

      cart = Commerce::Cart.find_by(user: current_user)
      subtotal_cents = cart&.subtotal_cents.to_i
      result = Commerce::PreviewCoupon.call(
        subtotal_cents: subtotal_cents,
        code: code,
        cart_items: cart_items,
        user: current_user
      )
      if result.success?
        session[:pending_coupon_code] = result.value[:code]
        result.value[:code]
      end
    end

    def resolve_pending_payment(order:, provider:, amount_cents:)
      order.payment_records.pending
        .where("amount_cents != ? OR provider != ?", amount_cents, provider)
        .update_all(status: "failed", updated_at: Time.current)

      order.payment_records.pending.find_by(amount_cents: amount_cents, provider: provider) ||
        Payments::Record.create!(
          order: order,
          provider: provider,
          amount_cents: amount_cents,
          currency: order.currency,
          status: :pending
        )
    end

    def checkout_redirect_path(order)
      order ? store_order_path(order) : store_checkout_path
    end
  end
end
