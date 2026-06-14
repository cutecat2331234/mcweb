class ApplicationController < ActionController::Base
  include Authentication
  include InstallationGuard
  include ServiceResponder
  include Pagy::Backend

  allow_browser versions: :modern

  stale_when_importmap_changes
end
