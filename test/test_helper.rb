ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/reporters"
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    setup do
      Rails.cache.clear
      InstallationLock.find_or_create_by!(id: 1) { |lock| lock.locked = false }
      InstallationLock.lock!(user: User.first || create_user) unless InstallationLock.locked?
    end

    def sign_in_as(user, remember_me: false, password: "password123")
      if is_a?(ActionDispatch::IntegrationTest)
        post identity_session_path, params: {
          session: { email: user.email, password: password, remember_me: remember_me ? "1" : "0" }
        }
        assert_response :redirect, "Sign in failed for #{user.email}"
        return
      end

      result = Identity::SessionManager.call(user: user, ip_address: "127.0.0.1", user_agent: "Test", remember_me: remember_me)
      token = result.value[:token]
      @current_session = result.value[:session]
      cookies.signed[:session_token] = token
      token
    end

    def create_user(attrs = {})
      password = attrs.delete(:password) || "password123"
      User.create!({
        email: "user#{SecureRandom.hex(4)}@example.com",
        username: "user#{SecureRandom.hex(4)}",
        password: password,
        password_confirmation: password,
        email_verified: true,
        email_verified_at: Time.current,
        locale: "zh-CN",
        time_zone: "Asia/Shanghai"
      }.merge(attrs))
    end

    def grant_permission(user, permission_key)
      permission = Permission.find_or_create_by!(key: permission_key) do |p|
        p.name = permission_key
        p.category = permission_key.split(".").first
      end
      role = Role.find_or_create_by!(key: "test_#{permission_key.tr('.', '_')}") do |r|
        r.name = permission_key
      end
      role.permissions << permission unless role.permissions.include?(permission)
      user.roles << role unless user.roles.include?(role)
    end
  end
end
