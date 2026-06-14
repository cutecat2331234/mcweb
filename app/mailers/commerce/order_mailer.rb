# frozen_string_literal: true

module Commerce
  class OrderMailer < ApplicationMailer
    def order_created(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_created")

      mail(to: @order.user.email, subject: "订单确认 #{@order.order_number}")
    end

    def payment_confirmed(order_id)
      @order = Commerce::Order.find(order_id)
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

    def order_fulfilled(order_id)
      @order = Commerce::Order.find(order_id)
      return unless commerce_email_enabled?(@order.user, "commerce.order_fulfilled")

      mail(to: @order.user.email, subject: "商品已发货 #{@order.order_number}")
    end

    def question_answered(user_id, question_id, answer_id)
      @user = User.find(user_id)
      @question = Commerce::ProductQuestion.find(question_id)
      @answer = Commerce::ProductAnswer.find(answer_id)
      @product = @question.product
      return unless commerce_email_enabled?(@user, "commerce.question_answered")

      mail(to: @user.email, subject: "你的商品问题已收到回复")
    end

    private

    def commerce_email_enabled?(user, notification_type)
      NotificationPreference.enabled?(user, channel: "email", notification_type: notification_type)
    end
  end
end
