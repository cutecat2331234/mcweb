# frozen_string_literal: true

class WebhookFailureAlertJob < ApplicationJob
  queue_as :mailers

  def perform
    WebhookFailureAlertCheck.call
  end
end
