ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
Commerce::InAppNotification # preload before parallel test workers fork
Commerce::MembershipSummary
Community::SectionModeration
Minecraft::SyncFilePath
require "rails/test_help"
require "minitest/reporters"
require "active_job/test_helper"
require "ostruct"

unless ENV["LOCKBOX_MASTER_KEY"].to_s.match?(/\A\h{64}\z/i)
  ENV["LOCKBOX_MASTER_KEY"] = "a" * 64
end
Lockbox.master_key = ENV["LOCKBOX_MASTER_KEY"]
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper
    parallelize(workers: :number_of_processors)

    parallelize_setup do
      I18n.reload!
    end

    setup do
      Rails.cache.clear
      RateLimitCounter.delete_all
      ensure_installation_locked!
      Frontend::TemplateStorage.ensure_root!
      disable_store_features!
      disable_forum_post_approval!
      reset_registration_user_fields!
      reset_refund_window!
    end

    def reset_registration_user_fields!
      Community::UserFieldDefinition.update_all(show_on_registration: false, required: false)
    end

    def ensure_installation_locked!
      return if is_a?(ActionDispatch::IntegrationTest) && self.class.name == "SetupWizardIntegrationTest"

      user = User.first || create_user
      InstallationLock.lock!(user: user)
      InstallationLock.where(locked: false).update_all(locked: true, locked_at: Time.current, locked_by_id: user.id)
    end

    def disable_forum_post_approval!
      SiteSetting.set("forum.require_post_approval_below_tl", "0")
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

    def grant_admin_module(user, module_key)
      user.admin_module_grants.find_or_create_by!(module_key: module_key) do |grant|
        grant.granted_at = Time.current
      end
    end

    def enable_store_feature!(feature_id)
      definition = Commerce::StoreFeatures.definition_for(feature_id)
      raise ArgumentError, "Unknown store feature: #{feature_id}" unless definition

      SiteSetting.set(definition.key, "true")
    end

    def disable_store_features!
      Commerce::StoreFeatures.definitions.each do |definition|
        SiteSetting.set(definition.key, "false")
      end
    end

    def reset_refund_window!
      SiteSetting.set("store.refund_window_days", "0")
    end

    def enable_refund_window!(days = 30)
      SiteSetting.set("store.refund_window_days", days.to_s)
    end

    def anchor_order_payment_at!(order, paid_at: 1.day.ago)
      order.payment_records.update_all(created_at: paid_at, updated_at: paid_at)
      Commerce::OrderEvent.where(order: order, to_status: "paid").delete_all
      Commerce::OrderEvent.create!(
        order: order,
        event_type: "paid",
        to_status: "paid",
        created_at: paid_at
      )
    end

    def ensure_connector_player_session!(server:, uuid:, username: "Player")
      player_ref = Minecraft::PlayerRef.resolve(uuid: uuid, platform: "java", username: username)
      Minecraft::PlayerSession.create!(
        player_profile: player_ref.profile,
        server: server,
        username: username,
        joined_at: Time.current,
        source: "test"
      )
      player_ref
    end

    def enable_forum_pm!(user)
      return if Community::TrustLevel.can_send_pm?(user)

      category = Community::Category.find_or_create_by!(slug: "pm-unlock-cat") { |c| c.name = "PM Unlock" }
      section = Community::Section.find_or_create_by!(category: category, slug: "pm-unlock-sec") do |s|
        s.name = "PM Unlock"
        s.position = 0
      end
      topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: user,
        title: "PM unlock #{SecureRandom.hex(4)}",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: user,
        replies_count: 0
      )
      Community::Post.create!(
        topic: topic,
        user: user,
        floor_number: 1,
        body: "Unlock PM",
        status: "published"
      )
    end
  end
end
