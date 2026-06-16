# frozen_string_literal: true

module Commerce
  class NotifyNewProductQuestion < ApplicationService
    STAFF_PERMISSIONS = %w[store.questions.answer store.questions.manage admin.access].freeze

    def initialize(question:)
      @question = question
      @product = question.product
      @asker = question.user
    end

    def call
      staff_ids = User
        .joins(roles: :permissions)
        .where(permissions: { key: STAFF_PERMISSIONS })
        .where.not(id: @asker.id)
        .distinct
        .pluck(:id)

      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @asker.id,
        recipient_ids: staff_ids
      ).value

      User.where(id: recipient_ids).find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "commerce.new_product_question")

        Notification.notify!(
          user: user,
          notification_type: "commerce.new_product_question",
          title: "新商品提问：#{@product.name}",
          body: @question.body.truncate(120),
          metadata: {
            path: "/app/store/products/#{@product.public_id}",
            product_public_id: @product.public_id,
            question_id: @question.id
          }
        )

        if NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.new_product_question")
          MailDeliveryJob.perform_later(
            "Commerce::OrderMailer",
            "new_product_question",
            "deliver_now",
            args: [ user.id, @question.id ]
          )
        end
      end

      ServiceResult.success
    end
  end
end
