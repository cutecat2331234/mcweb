# frozen_string_literal: true

module Commerce
  class OrderMailer < ApplicationMailer
    def order_created(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_created")

      assign_payment_deadline!(@order)
      mail(to: @order.user.email, subject: "订单确认 #{@order.order_number}")
    end

    def payment_reminder(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.payment_reminder")

      assign_payment_deadline!(@order)
      mail(to: @order.user.email, subject: "请尽快支付订单 #{@order.order_number}")
    end

    def payment_confirmed(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.payment_confirmed")

      mail(to: @order.user.email, subject: "支付成功 #{@order.order_number}")
    end

    def order_cancelled(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_cancelled")

      mail(to: @order.user.email, subject: "订单已取消 #{@order.order_number}")
    end

    def refund_processed(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      return unless commerce_email_enabled?(@order.user, "commerce.refund_processed")

      mail(to: @order.user.email, subject: "退款处理通知 #{@order.order_number}")
    end

    def refund_rejected(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      return unless commerce_email_enabled?(@order.user, "commerce.refund_rejected")

      mail(to: @order.user.email, subject: "退款申请未通过 #{@order.order_number}")
    end

    def order_processing(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_processing")

      mail(to: @order.user.email, subject: "订单处理中 #{@order.order_number}")
    end

    def order_fulfilling(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_fulfilling")

      mail(to: @order.user.email, subject: "订单发货处理中 #{@order.order_number}")
    end

    def order_completed(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_completed")

      mail(to: @order.user.email, subject: "订单已完成 #{@order.order_number}")
    end

    def refund_requested(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      return unless commerce_email_enabled?(@order.user, "commerce.refund_requested")

      mail(to: @order.user.email, subject: "退款申请已提交 #{@order.order_number}")
    end

    def price_drop(user_id, product_id, baseline_cents, current_cents)
      @user = User.find(user_id)
      @product = Commerce::Product.find(product_id)
      return unless commerce_email_enabled?(@user, "commerce.price_drop")

      @baseline = baseline_cents
      @current = current_cents
      @url = "#{root_url.chomp('/')}#{"/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: "商品降价：#{@product.name}")
    end

    def order_fulfilled(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_fulfilled")

      mail(to: @order.user.email, subject: "商品已发货 #{@order.order_number}")
    end

    def order_shipped(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_shipped")

      @tracking_url = Commerce::TrackingUrl.for_order(@order)
      mail(to: @order.user.email, subject: "订单已发货 #{@order.order_number}")
    end

    def question_answered(user_id, question_id, answer_id)
      @user = User.find(user_id)
      @question = Commerce::ProductQuestion.find(question_id)
      @answer = Commerce::ProductAnswer.find(answer_id)
      @product = @question.product
      return unless commerce_email_enabled?(@user, "commerce.question_answered")

      mail(to: @user.email, subject: "你的商品问题已收到回复")
    end

    def product_changelog(user_id, product_id)
      @user = User.find(user_id)
      @product = Commerce::Product.find(product_id)
      return unless commerce_email_enabled?(@user, "commerce.product_changelog")

      @url = "#{root_url.chomp('/')}#{"/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: "商品更新：#{@product.name}")
    end

    def new_product_question(user_id, question_id)
      @user = User.find(user_id)
      @question = Commerce::ProductQuestion.find(question_id)
      @product = @question.product
      return unless commerce_email_enabled?(@user, "commerce.new_product_question")

      @url = "#{root_url.chomp('/')}#{"/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: "新商品提问：#{@product.name}")
    end

    def merchant_review_reply(review_id)
      @review = Commerce::Review.includes(:product, :user).find(review_id)
      @user = @review.user
      @product = @review.product
      return unless commerce_email_enabled?(@user, "commerce.merchant_review_reply")

      @url = "#{root_url.chomp('/')}#{"/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: "商家回复了你的评价：#{@product.name}")
    end

    def review_request(order_id)
      @order = Commerce::Order.includes(:items).find(order_id)
      @user = @order.user
      return unless commerce_email_enabled?(@user, "commerce.review_request")

      @url = "#{root_url.chomp('/')}#{"/store/orders/#{@order.public_id}"}"
      mail(to: @user.email, subject: "邀请你评价订单 #{@order.order_number}")
    end

    private

    def commerce_email_enabled?(user, notification_type)
      NotificationPreference.enabled?(user, channel: "email", notification_type: notification_type)
    end

    def assign_payment_deadline!(order)
      return unless order.pending? || order.awaiting_payment?
      return if order.total_cents.to_i <= 0

      minutes = SiteSetting.get("store.pending_order_expiry_minutes", "30").to_i
      minutes = 30 if minutes <= 0
      expires = order.created_at + minutes.minutes
      @expires_label = expires.future? ? I18n.l(expires, format: :short) : nil
      @pay_url = "#{root_url.chomp('/')}#{"/store/orders/#{order.public_id}"}"
    end
  end
end
