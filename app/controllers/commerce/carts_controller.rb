# frozen_string_literal: true

module Commerce
  class CartsController < ApplicationController
    include Commerce::CodePreviewRateLimitable

    before_action :set_cart
    before_action :require_cart_writable!, except: %i[show preview_coupon preview_gift_card]

    def show
      session.delete(:cart_recovery_readonly) if params[:recovery].blank?

      items = @cart.items.includes(:product, :variant)
      blocked_count = items.count { |item| item.product && !Commerce::StoreFeatures.product_visible?(item.product) }
      visible_items = items.select { |item| item.product && Commerce::StoreFeatures.product_visible?(item.product) }
      pending_coupon = apply_coupon_from_url!(items)
      pending_coupon ||= session[:pending_coupon_code].to_s.presence
      pending_gift_card = session[:pending_gift_card_code].to_s.presence
      currency = visible_items.first&.product&.currency || items.first&.product&.currency || "CNY"
      subtotal_cents = visible_items.sum(&:total_cents)
      coupon = Commerce::Coupon.find_by(code: pending_coupon) if pending_coupon.present?

      render inertia: "Commerce/Carts/Show", props: {
        items: visible_items.map { |item| serialize_cart_item(item) },
        blockedItemCount: blocked_count,
        subtotalLabel: format_money(subtotal_cents, currency),
        subtotalCents: subtotal_cents,
        loggedIn: logged_in?,
        pendingCouponCode: pending_coupon,
        pendingGiftCardCode: pending_gift_card,
        couponAutoApplied: params[:coupon].present? && pending_coupon.present?,
        previewCouponUrl: preview_coupon_store_cart_path,
        previewGiftCardUrl: preview_gift_card_store_cart_path,
        clearCouponUrl: clear_coupon_store_cart_path,
        clearGiftCardUrl: clear_gift_card_store_cart_path,
        moveToWishlistUrl: move_to_wishlist_store_cart_path,
        clearCartUrl: clear_store_cart_path,
        crossSellProducts: cross_sell_products(visible_items),
        cartRecovered: params[:recovery].present? && @cart.recovery_token == params[:recovery].to_s,
        **serialize_shipping_quote(subtotal_cents, currency: currency, cart_items: visible_items, coupon: coupon)
      }
    end

    def clear
      result = Commerce::ClearCart.call(cart: @cart)

      if result.success?
        redirect_to store_cart_path, notice: t("mcweb.flash.cart_cleared")
      else
        redirect_to store_cart_path, alert: service_error_message(result)
      end
    end

    def move_to_wishlist
      return redirect_to store_cart_path, alert: t("mcweb.flash.sign_in_required_short") unless logged_in?

      item = @cart.items.find(params[:item_id])
      result = Commerce::MoveCartItemToWishlist.call(user: current_user, cart_item: item)

      if result.success?
        redirect_to store_cart_path, notice: t("mcweb.flash.moved_to_wishlist")
      else
        redirect_to store_cart_path, alert: service_error_message(result)
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to store_cart_path, alert: t("mcweb.flash.cart_item_missing")
    end

    def preview_coupon
      return render_preview_rate_limited if preview_rate_limited?

      subtotal_cents = @cart.subtotal_cents
      cart_items = @cart.items.includes(:product)
      currency = cart_items.first&.product&.currency || "CNY"
      result = Commerce::PreviewCoupon.call(
        subtotal_cents: subtotal_cents,
        code: params[:code],
        cart_items: cart_items,
        user: current_user
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

    def clear_coupon
      session.delete(:pending_coupon_code)
      redirect_to store_cart_path, notice: t("mcweb.flash.coupon_cleared")
    end

    def preview_gift_card
      return render_preview_rate_limited if preview_rate_limited?

      subtotal_cents = @cart.subtotal_cents
      discount_cents = 0
      if session[:pending_coupon_code].present?
        preview = Commerce::PreviewCoupon.call(
          subtotal_cents: subtotal_cents,
          code: session[:pending_coupon_code],
          cart_items: @cart.items.includes(:product),
          user: current_user
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
        shipping_cents: shipping_cents
      )

      if result.success?
        session[:pending_gift_card_code] = result.value[:code]
        currency = @cart.items.first&.product&.currency || "CNY"
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

    def clear_gift_card
      session.delete(:pending_gift_card_code)
      redirect_to store_cart_path, notice: t("mcweb.flash.gift_card_cleared")
    end

    def update
      if params[:product_id].present?
        product = Commerce::Product.available.find_by(public_id: params[:product_id]) ||
                  Commerce::Product.available.find_by(id: params[:product_id])
        unless product && Commerce::StoreFeatures.product_visible?(product)
          return redirect_to safe_referer_path(fallback: store_cart_path), alert: t("mcweb.flash.product_not_found")
        end
        variant = product.variants.find_by(id: params[:variant_id])
        quantity = params[:quantity].to_i
        quantity = 1 if quantity < 1

        validation = Commerce::ValidateCartItem.call(
          user: current_user,
          product: product,
          variant: variant,
          quantity: quantity,
          cart: @cart
        )
        unless validation.success?
          return redirect_to safe_referer_path(fallback: store_cart_path), alert: service_error_message(validation)
        end

        @cart.add_item!(product: product, variant: variant, quantity: quantity)
      elsif params[:item_id].present? && params.key?(:gift_note)
        item = @cart.items.find(params[:item_id])
        item.update!(gift_note: params[:gift_note].to_s.strip.presence)
        @cart.reset_abandoned_reminder!
      elsif params[:item_id].present?
        item = @cart.items.find(params[:item_id])
        if params[:quantity].to_i.positive?
          validation = Commerce::ValidateCartItem.call(
            user: current_user,
            product: item.product,
            variant: item.variant,
            quantity: params[:quantity].to_i,
            cart: @cart,
            replace_quantity: true
          )
          unless validation.success?
            return redirect_to store_cart_path, alert: service_error_message(validation)
          end

          item.update!(quantity: params[:quantity].to_i)
        else
          item.destroy!
        end
        @cart.reset_abandoned_reminder!
      end

      redirect_to store_cart_path, notice: t("mcweb.flash.cart_updated")
    rescue ActiveRecord::RecordNotFound
      redirect_to store_cart_path, alert: t("mcweb.flash.cart_item_missing")
    rescue ActiveRecord::RecordInvalid
      redirect_to store_cart_path, alert: t("mcweb.flash.cart_update_failed")
    end

    private

    def set_cart
      @cart_recovery_readonly = false

      if params[:recovery].present?
        recovered = Commerce::Cart.find_by(recovery_token: params[:recovery])
        if recovered && !recovered.empty? && recoverable_cart?(recovered)
          @cart = recovered
          if recovered.user_id.present? && !logged_in?
            @cart_recovery_readonly = true
            session[:cart_recovery_readonly] = true
          else
            session.delete(:cart_recovery_readonly)
            persist_cart_cookie(@cart) unless logged_in?
          end
          return
        end
      end

      @cart = find_user_cart || find_session_cart || create_session_cart
      session.delete(:cart_recovery_readonly) if logged_in?
      persist_cart_cookie(@cart) unless logged_in?
    end

    def recoverable_cart?(cart)
      if params[:recovery].present? && cart.recovery_token == params[:recovery].to_s
        if cart.user_id.present? && logged_in? && cart.user_id != current_user.id
          return false
        end

        return !cart.empty?
      end

      return false if cart.user_id.present? && !logged_in?

      return true unless logged_in?

      cart.user_id.nil? || cart.user_id == current_user.id
    end

    def require_cart_writable!
      return if cart_writable?

      redirect_to store_cart_path, alert: t("mcweb.flash.sign_in_required_short")
    end

    def cart_writable?
      return false if @cart_recovery_readonly || session[:cart_recovery_readonly]
      return true if @cart.user_id.nil?

      logged_in? && @cart.user_id == current_user.id
    end

    def find_user_cart
      return unless logged_in?

      Commerce::Cart.find_or_create_by!(user: current_user)
    end

    def find_session_cart
      token = cookies.signed[:cart_token]
      Commerce::Cart.find_by(session_token: token) if token.present?
    end

    def create_session_cart
      Commerce::Cart.create!
    end

    def persist_cart_cookie(cart)
      cookies.signed[:cart_token] = {
        value: cart.session_token,
        httponly: true,
        same_site: :lax,
        expires: 30.days
      }
    end

    def cross_sell_products(items)
      return [] if items.blank?

      cart_product_ids = items.map(&:store_product_id)
      category_ids = items.filter_map { |item| item.product&.store_category_id }.uniq
      return [] if category_ids.empty?

      scope = Commerce::StoreFeatures.visible_products_scope(
        Commerce::Product.available
          .where(store_category_id: category_ids)
          .where.not(id: cart_product_ids)
          .order(created_at: :desc)
          .limit(4)
      )

      scope.map { |product| serialize_product_list_item(product) }
    end

    def shipping_cents_for_preview(subtotal_cents, coupon_code: nil)
      cart_items = @cart.items.includes(:product)
      coupon = Commerce::Coupon.find_by(code: coupon_code) if coupon_code.present?
      coupon ||= Commerce::Coupon.find_by(code: session[:pending_coupon_code]) if session[:pending_coupon_code].present?
      result = Commerce::CalculateShipping.call(subtotal_cents: subtotal_cents, cart_items: cart_items, coupon: coupon)
      result.success? ? result.value[:shipping_cents].to_i : 0
    end

    def apply_coupon_from_url!(cart_items)
      code = params[:coupon].to_s.strip
      return nil if code.blank?
      return nil if preview_rate_limited?

      result = Commerce::PreviewCoupon.call(
        subtotal_cents: @cart.subtotal_cents,
        code: code,
        cart_items: cart_items,
        user: current_user
      )
      if result.success?
        session[:pending_coupon_code] = result.value[:code]
        result.value[:code]
      end
    end
  end
end
