class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
  helper ApplicationHelper
  helper Rails.application.routes.url_helpers
end
