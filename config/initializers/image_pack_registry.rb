# frozen_string_literal: true

Rails.application.config.after_initialize do
  Mcweb::ImagePackRegistry.ensure_config! unless Rails.env.test?
end
