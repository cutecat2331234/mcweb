# frozen_string_literal: true

module Commerce
  class NotifyProductQuestionAnswered < ApplicationService
    def initialize(question:, answer:)
      @question = question
      @answer = answer
      @asker = question.user
    end

    def call
      return ServiceResult.success if @asker.id == @answer.user_id
      return ServiceResult.success unless NotificationPreference.enabled?(@asker, channel: "email", notification_type: "commerce.question_answered")

      MailDeliveryJob.perform_later(
        "Commerce::OrderMailer",
        "question_answered",
        "deliver_now",
        args: [ @asker.id, @question.id, @answer.id ]
      )

      ServiceResult.success
    end
  end
end
