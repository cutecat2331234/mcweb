# frozen_string_literal: true

Rails.application.config.after_initialize do
  Operations::Metrics::Instrumentation.install! unless Rails.env.test?
end
