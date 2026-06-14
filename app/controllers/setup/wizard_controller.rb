# frozen_string_literal: true

module Setup
  class WizardController < ApplicationController
    STEPS = %w[site admin complete].freeze

    def index
      redirect_to setup_step_path(STEPS.first)
    end

    def show
      @step = params[:step]
      return redirect_to setup_root_path unless STEPS.include?(@step)

      @settings = wizard_session_data
    end

    def update
      @step = params[:step]
      return redirect_to setup_root_path unless STEPS.include?(@step)

      save_step_data(@step, step_params)
      next_step = STEPS[STEPS.index(@step) + 1]
      redirect_to next_step ? setup_step_path(next_step) : setup_complete_path
    end

    def complete
      data = wizard_session_data
      admin_data = data["admin"] || {}

      result = Identity::RegisterUser.call(
        email: admin_data["email"],
        username: admin_data["username"],
        password: admin_data["password"],
        display_name: admin_data["display_name"]
      )

      unless result.success?
        flash[:alert] = service_error_message(result)
        return redirect_to setup_step_path("admin")
      end

      user = result.value[:user]
      user.update!(email_verified: true, email_verified_at: Time.current)

      admin_role = Role.find_or_create_by!(key: "admin", name: "Administrator", system_role: true)
      user.roles << admin_role unless user.roles.include?(admin_role)

      site_data = data["site"] || {}
      SiteSetting.set("site.name", site_data["name"]) if site_data["name"].present?
      SiteSetting.set("site.url", site_data["url"]) if site_data["url"].present?

      InstallationLock.lock!(user: user)
      session.delete(:setup_wizard)

      redirect_to identity_sign_in_path, notice: "Setup complete. Sign in with your administrator account."
    end

    private

    def step_params
      case @step
      when "site"
        params.expect(setup: %i[name url])[:setup]
      when "admin"
        params.expect(setup: %i[email username password display_name])[:setup]
      else
        {}
      end
    end

    def wizard_session_data
      session[:setup_wizard] ||= {}
    end

    def save_step_data(step, data)
      wizard_session_data[step] = data.to_h
      session[:setup_wizard] = wizard_session_data
    end
  end
end
