# frozen_string_literal: true

class MailDeliveryJob < ApplicationJob
  queue_as :mailers

  def perform(mailer_class, mail_method, delivery_method, args:)
    mailer_class.constantize.public_send(mail_method, *args).public_send(delivery_method)
  end
end
