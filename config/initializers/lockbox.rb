# frozen_string_literal: true

Lockbox.master_key = ENV.fetch("LOCKBOX_MASTER_KEY") do
  Rails.application.credentials.dig(:lockbox, :master_key) || "0" * 64
end
