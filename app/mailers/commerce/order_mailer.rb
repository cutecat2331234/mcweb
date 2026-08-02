# frozen_string_literal: true

module Commerce
  class OrderMailer < ApplicationMailer
    def order_created(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_created")

      assign_payment_deadline!(@order)
      mail(to: @order.user.email, subject: commerce_subject(:order_created, number: @order.order_number))
    end

    def payment_reminder(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.payment_reminder")

      assign_payment_deadline!(@order)
      mail(to: @order.user.email, subject: commerce_subject(:payment_reminder, number: @order.order_number))
    end

    def payment_confirmed(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.payment_confirmed")

      mail(to: @order.user.email, subject: commerce_subject(:payment_confirmed, number: @order.order_number))
    end

    def order_cancelled(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_cancelled")

      mail(to: @order.user.email, subject: commerce_subject(:order_cancelled, number: @order.order_number))
    end

    def refund_processed(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      return unless commerce_email_enabled?(@order.user, "commerce.refund_processed")

      mail(to: @order.user.email, subject: commerce_subject(:refund_processed, number: @order.order_number))
    end

    def refund_rejected(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      return unless commerce_email_enabled?(@order.user, "commerce.refund_rejected")

      mail(to: @order.user.email, subject: commerce_subject(:refund_rejected, number: @order.order_number))
    end

    def order_processing(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_processing")

      mail(to: @order.user.email, subject: commerce_subject(:order_processing, number: @order.order_number))
    end

    def order_fulfilling(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_fulfilling")

      mail(to: @order.user.email, subject: commerce_subject(:order_fulfilling, number: @order.order_number))
    end

    def order_completed(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_completed")

      mail(to: @order.user.email, subject: commerce_subject(:order_completed, number: @order.order_number))
    end

    def refund_requested(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      return unless commerce_email_enabled?(@order.user, "commerce.refund_requested")

      mail(to: @order.user.email, subject: commerce_subject(:refund_requested, number: @order.order_number))
    end

    def price_drop(user_id, product_id, baseline_cents, current_cents)
      @user = User.find(user_id)
      @product = Commerce::Product.find(product_id)
      return unless commerce_email_enabled?(@user, "commerce.price_drop")

      @baseline = baseline_cents
      @current = current_cents
      @url = "#{root_url.chomp('/')}#{"/app/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: commerce_subject(:price_drop, product: @product.name))
    end

    def order_fulfilled(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_fulfilled")

      mail(to: @order.user.email, subject: commerce_subject(:order_fulfilled, number: @order.order_number))
    end

    def order_shipped(order_id)
      @order = Commerce::Order.includes(:items, :coupon, :gift_card).find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_shipped")

      @tracking_url = Commerce::TrackingUrl.for_order(@order)
      mail(to: @order.user.email, subject: commerce_subject(:order_shipped, number: @order.order_number))
    end

    def question_answered(user_id, question_id, answer_id)
      @user = User.find(user_id)
      @question = Commerce::ProductQuestion.find(question_id)
      @answer = Commerce::ProductAnswer.find(answer_id)
      @product = @question.product
      return unless commerce_email_enabled?(@user, "commerce.question_answered")

      mail(to: @user.email, subject: commerce_subject(:question_answered, product: @product.name))
    end

    def product_changelog(user_id, product_id)
      @user = User.find(user_id)
      @product = Commerce::Product.find(product_id)
      return unless commerce_email_enabled?(@user, "commerce.product_changelog")

      @url = "#{root_url.chomp('/')}#{"/app/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: commerce_subject(:product_changelog, product: @product.name))
    end

    def new_product_question(user_id, question_id)
      @user = User.find(user_id)
      @question = Commerce::ProductQuestion.find(question_id)
      @product = @question.product
      return unless commerce_email_enabled?(@user, "commerce.new_product_question")

      @url = "#{root_url.chomp('/')}#{"/app/store/products/#{@product.public_id}"}"
      mail(to: @user.email, subject: commerce_subject(:new_product_question, product: @product.name))
    end

    def merchant_review_reply(review_id)
      @review = Commerce::Review.includes(:product, :user).find(review_id)
      @user = @review.user
      @product = @review.product
      return unless commerce_email_enabled?(@user, "commerce.merchant_review_reply")

      @url = "#{root_url.chomp('/')}#{Mcweb::Paths.normalize("/store/products/#{@product.public_id}")}"
      mail(to: @user.email, subject: commerce_subject(:merchant_review_reply, product: @product.name))
    end

    def review_request(order_id)
      @order = Commerce::Order.includes(:items).find(order_id)
      @user = @order.user
      return unless commerce_email_enabled?(@user, "commerce.review_request")

      @url = "#{root_url.chomp('/')}#{Mcweb::Paths.normalize("/store/orders/#{@order.public_id}")}"
      mail(to: @user.email, subject: commerce_subject(:review_request, number: @order.order_number))
    end

    private

    def commerce_email_enabled?(user, notification_type)
      NotificationPreference.enabled?(user, channel: "email", notification_type: notification_type)
    end

    def commerce_subject(name, **options)
      recipient_t("mcweb.mail.commerce.subjects.#{name}", **options)
    end

    def assign_payment_deadline!(order)
      return unless order.pending? || order.awaiting_payment?
      return if order.total_cents.to_i <= 0

      minutes = SiteSetting.get("store.pending_order_expiry_minutes", "30").to_i
      minutes = 30 if minutes <= 0
      expires = order.created_at + minutes.minutes
      @expires_label = expires.future? ? recipient_l(expires, format: :short) : nil
      @pay_url = "#{root_url.chomp('/')}#{Mcweb::Paths.normalize("/store/orders/#{order.public_id}")}"
    end
  end
end
