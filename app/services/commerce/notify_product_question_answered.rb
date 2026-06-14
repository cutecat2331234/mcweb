# frozen_string_literal: true

module Commerce
  class NotifyProductQuestionAnswered < ApplicationService
    def initialize(question:, answer:)
      @question = question
      @answer = answer
      @asker = question.user
      @product = question.product
    end

    def call
      return ServiceResult.success if @asker.id == @answer.user_id

      if NotificationPreference.enabled?(@asker, channel: "in_app", notification_type: "commerce.question_answered")
        Notification.notify!(
          user: @asker,
          notification_type: "commerce.question_answered",
          title: "你的问题收到回复",
          body: @answer.body.truncate(200),
          metadata: {
            path: "/store/products/#{@product.public_id}",
            question_id: @question.id,
            answer_id: @answer.id
          }
        )
      end

      if NotificationPreference.enabled?(@asker, channel: "email", notification_type: "commerce.question_answered")
        MailDeliveryJob.perform_later(
          "Commerce::OrderMailer",
          "question_answered",
          "deliver_now",
          args: [ @asker.id, @question.id, @answer.id ]
        )
      end

      ServiceResult.success
    end
  end
end
