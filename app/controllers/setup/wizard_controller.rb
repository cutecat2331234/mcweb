# frozen_string_literal: true

module Setup
  class WizardController < ApplicationController
    layout "setup"

    STEPS = %w[site admin].freeze

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

      if @step == "admin"
        return finalize_setup(step_params)
      end

      save_step_data(@step, step_params)
      redirect_to setup_step_path(STEPS[STEPS.index(@step) + 1])
    end

    # 保留路由兼容；安装应在 admin 步骤提交时同步完成，避免密码写入 session 后丢失。
    def complete
      data = wizard_session_data
      admin_data = data.fetch("admin", {}).with_indifferent_access

      if admin_data[:password].present?
        finalize_setup(admin_data)
      else
        flash[:alert] = t("mcweb.setup.password_required")
        redirect_to setup_step_path("admin")
      end
    end

    private

    def finalize_setup(admin_params)
      admin_data = admin_params.to_h.with_indifferent_access
      site_data = wizard_session_data.fetch("site", {}).with_indifferent_access

      password = admin_data[:password].to_s

      if password.blank?
        flash[:alert] = t("mcweb.setup.password_required")
        return redirect_to setup_step_path("admin")
      end

      if password.length < 6
        flash[:alert] = t("mcweb.setup.password_too_short")
        return redirect_to setup_step_path("admin")
      end

      confirmation = admin_data[:password_confirmation].to_s
      if confirmation.present? && confirmation != password
        flash[:alert] = t("mcweb.setup.password_mismatch")
        return redirect_to setup_step_path("admin")
      end

      save_step_data("admin", admin_data.except(:password, :password_confirmation).merge("password" => "[FILTERED]"))

      result = Identity::RegisterUser.call(
        email: admin_data[:email],
        username: admin_data[:username],
        password: password,
        display_name: admin_data[:display_name]
      )

      unless result.success?
        flash[:alert] = service_error_message(result)
        return redirect_to setup_step_path("admin")
      end

      user = result.value[:user]
      user.update!(email_verified: true, email_verified_at: Time.current, account_type: :owner)

      Rails.application.load_seed unless Role.exists?(key: "owner")
      admin_role = Role.find_by!(key: "owner")
      user.roles << admin_role unless user.roles.include?(admin_role)

      SiteSetting.set("site.name", site_data[:name]) if site_data[:name].present?
      SiteSetting.set("site.url", site_data[:url]) if site_data[:url].present?

      InstallationLock.lock!(user: user)
      Frontend::EnsureDefaultTemplate.call
      session.delete(:setup_wizard)

      redirect_to identity_sign_in_path, notice: t("mcweb.flash.setup_complete")
    end

    def step_params
      case @step
      when "site"
        params.require(:setup).permit(:name, :url)
      when "admin"
        params.require(:setup).permit(:email, :username, :password, :password_confirmation, :display_name)
      else
        {}
      end
    end

    def wizard_session_data
      session[:setup_wizard] ||= {}
    end

    def save_step_data(step, data)
      wizard_session_data[step.to_s] = data.to_h.stringify_keys
      session[:setup_wizard] = wizard_session_data
    end
  end
end
