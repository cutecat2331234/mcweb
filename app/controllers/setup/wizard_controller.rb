# frozen_string_literal: true

module Setup
  class WizardController < ApplicationController
    layout "setup"

    before_action :ensure_setup_accessible!
    before_action :rate_limit_setup_step!, only: :update

    STEPS = %w[database site admin].freeze

    def index
      redirect_to setup_step_path(first_step)
    end

    def show
      @step = params[:step]
      return redirect_to setup_root_path unless STEPS.include?(@step)
      return redirect_to setup_step_path(first_step) if step_locked?(@step)
      return redirect_completed_setup if @step == "admin" && (InstallationLock.locked? || installation_owner_exists?)

      @settings = wizard_session_data
    end

    def update
      @step = params[:step]
      return redirect_to setup_root_path unless STEPS.include?(@step)
      return redirect_to setup_step_path(first_step) if step_locked?(@step)

      case @step
      when "database"
        handle_database_step(step_params)
      when "admin"
        finalize_setup(step_params)
      else
        save_step_data(@step, step_params)
        redirect_to setup_step_path(STEPS[STEPS.index(@step) + 1])
      end
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

    def first_step
      Mcweb::LocalConfig.complete? ? "site" : "database"
    end

    def step_locked?(step)
      step_index = STEPS.index(step)
      return true if step_index.nil?

      STEPS.take(step_index).any? do |required_step|
        required_step == "database" && !Mcweb::LocalConfig.complete?
      end
    end

    def handle_database_step(params)
      data = params.to_h.with_indifferent_access
      database_name = data[:development_database].presence || Mcweb::LocalConfig.default_database_name("development")

      test_result = Mcweb::TestDatabaseConnection.call(
        host: data[:host],
        port: data[:port],
        username: data[:username],
        password: data[:password],
        database: database_name
      )
      unless test_result.success?
        flash[:alert] = service_error_message(test_result)
        return redirect_to setup_step_path("database")
      end

      Mcweb::LocalConfig.write!(
        "database" => {
          "host" => data[:host],
          "port" => data[:port].to_i,
          "username" => data[:username],
          "password" => data[:password],
          "development" => database_name,
          "test" => data[:test_database].presence || Mcweb::LocalConfig.default_database_name("test"),
          "production" => data[:production_database].presence || Mcweb::LocalConfig.default_database_name("production")
        }
      )

      prepare_result = Mcweb::PrepareApplicationDatabase.call
      unless prepare_result.success?
        flash[:alert] = service_error_message(prepare_result)
        return redirect_to setup_step_path("database")
      end

      # db:prepare 会重连数据库，需在此重新解锁以继续安装向导
      InstallationLock.unlock!

      save_step_data("database", data.except(:password).merge("password" => "[FILTERED]"))
      redirect_to setup_step_path("site"), notice: t("mcweb.setup.database_saved")
    end

    def finalize_setup(admin_params)
      if InstallationLock.locked? || installation_owner_exists?
        return redirect_completed_setup
      end

      unless wizard_session_data["database"].present?
        flash[:alert] = t("mcweb.setup.complete_prior_steps")
        return redirect_to setup_step_path(first_step)
      end

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

      outcome = :unknown
      register_error = nil
      user = nil

      ActiveRecord::Base.transaction do
        acquire_installation_finalize_lock!

        if InstallationLock.locked? || installation_owner_exists?
          outcome = :already_complete
          next
        end

        result = Identity::RegisterUser.call(
          email: admin_data[:email],
          username: admin_data[:username],
          password: password,
          display_name: admin_data[:display_name],
          ip_address: request.remote_ip
        )

        unless result.success?
          outcome = :register_failed
          register_error = service_error_message(result)
          raise ActiveRecord::Rollback
        end

        user = result.value[:user]
        user.update!(email_verified: true, email_verified_at: Time.current, account_type: :owner)

        Rails.application.load_seed unless Role.exists?(key: "owner")
        admin_role = Role.find_by!(key: "owner")
        user.roles << admin_role unless user.roles.include?(admin_role)

        SiteSetting.set("site.name", site_data[:name]) if site_data[:name].present?
        SiteSetting.set("site.url", site_data[:url]) if site_data[:url].present?

        InstallationLock.lock!(user: user)
        outcome = :success
      end

      case outcome
      when :already_complete
        redirect_completed_setup
      when :register_failed
        flash[:alert] = register_error
        redirect_to setup_step_path("admin")
      when :success
        Frontend::EnsureDefaultTemplate.call
        session.delete(:setup_wizard)
        redirect_to identity_sign_in_path,
                    notice: t("mcweb.flash.setup_complete_with_account", email: user.email)
      else
        redirect_completed_setup
      end
    end

    def step_params
      case @step
      when "database"
        params.require(:setup).permit(
          :host,
          :port,
          :username,
          :password,
          :development_database,
          :test_database,
          :production_database
        )
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

    def installation_owner_exists?
      User.exists?(account_type: :owner)
    end

    def redirect_completed_setup
      redirect_to identity_sign_in_path, alert: t("mcweb.setup.already_complete")
    end

    def acquire_installation_finalize_lock!
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)", INSTALLATION_FINALIZE_LOCK_KEY ])
      )
    end

    def ensure_setup_accessible!
      return if Rails.env.local?
      return if request.local?

      expected = setup_access_token
      if expected.blank?
        head :forbidden
        return
      end

      supplied = params[:setup_token].presence || session[:setup_access_token].presence ||
        request.headers["X-Setup-Token"].presence
      if supplied.present? && ActiveSupport::SecurityUtils.secure_compare(supplied.to_s, expected)
        session[:setup_access_token] = supplied
        return
      end

      head :forbidden
    end

    def setup_access_token
      ENV["SETUP_ACCESS_TOKEN"].presence || Rails.application.credentials.dig(:setup, :access_token)
    end

    def rate_limit_setup_step!
      result = Administration::RateLimiter.call(
        key: "setup_wizard:#{request.remote_ip}",
        limit: 30,
        window: 15.minutes
      )
      return unless result.failure?

      flash[:alert] = t("mcweb.flash.rate_limited", default: "操作过于频繁，请稍后再试。")
      redirect_to setup_step_path(@step.presence || first_step)
    end

    INSTALLATION_FINALIZE_LOCK_KEY = 748_239_013
  end
end
