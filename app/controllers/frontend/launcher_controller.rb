# frozen_string_literal: true

module Frontend
  class LauncherController < ApplicationController
    def show
      application = Frontend::ApplicationRegistry.instance.launcher_application("/app")
      raise Frontend::ApplicationRegistry::UnknownApplication, "no /app launcher is registered" unless application

      redirect_to application.landing_path
    end
  end
end
