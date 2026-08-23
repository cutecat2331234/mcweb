# frozen_string_literal: true

Rails.application.reloader.to_prepare do
  Frontend::ApplicationRegistry.reload!.validate_runtime_files!
end
