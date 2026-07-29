# frozen_string_literal: true

require "uri"

class PluginDeliveryMailer < ApplicationMailer
  def delivery(delivery_id)
    @delivery = PluginOutboundDelivery.find(delivery_id)
    @user = @delivery.user
    @text_body = @delivery.payload.fetch("text_body").to_s
    @html_body = @delivery.payload["html_body"].to_s.presence
    headers["Message-ID"] = "<mcweb-plugin-#{@delivery.public_id}@#{message_id_host}>"
    mail(to: @user.email, subject: @delivery.payload.fetch("subject").to_s)
  end

  private

  def message_id_host
    URI.parse(SiteSetting.get("site.url", "http://localhost").to_s).host.presence || "localhost"
  rescue URI::InvalidURIError
    "localhost"
  end
end
