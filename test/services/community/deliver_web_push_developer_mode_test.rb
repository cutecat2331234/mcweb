# frozen_string_literal: true

require "test_helper"

module Community
  class DeliverWebPushDeveloperModeTest < ActiveSupport::TestCase
    setup do
      suffix = SecureRandom.hex(4)
      @user = create_user
      @notification = Notification.create!(
        user: @user,
        notification_type: "forum.new_follower",
        title: "Developer Mode push",
        body: "Captured locally"
      )
      @subscription = Community::PushSubscription.create!(
        user: @user,
        endpoint: "https://push.example.test/#{suffix}",
        p256dh_key: "p256dh-#{suffix}",
        auth_key: "auth-#{suffix}"
      )
      NotificationPreference.set!(
        @user,
        channel: "web_push",
        notification_type: @notification.notification_type,
        enabled: true
      )
    end

    test "capture mode rechecks access and captures without network or VAPID keys" do
      access_checks = []
      capture_arguments = []
      visible = lambda do |notification:, user:|
        access_checks << [ notification.id, user.id ]
        true
      end
      capture = lambda do |**arguments|
        capture_arguments << arguments
        Mcweb::DeveloperModeCapture::Capture.new(
          capture_id: "capture-web-push-1",
          path: Pathname("/tmp/developer-mode/web-push/2026-07-26.jsonl")
        )
      end

      result = with_developer_mode(enabled: true) do
        with_singleton_method(Community::NotificationAccess, :visible?, visible) do
          with_singleton_method(
            Mcweb::DeveloperModeCapture,
            :capture_web_push!,
            capture
          ) do
            without_real_web_push do
              Community::DeliverWebPush.call(notification: @notification)
            end
          end
        end
      end

      assert_predicate result, :success?
      assert_equal true, result.value.fetch(:captured)
      assert_equal 1, result.value.fetch(:capture_count)
      assert_equal 1, result.value.fetch(:subscription_count)
      assert_equal [ "capture-web-push-1" ], result.value.fetch(:capture_ids)
      assert_equal [ "/tmp/developer-mode/web-push/2026-07-26.jsonl" ],
        result.value.fetch(:capture_paths)
      assert_equal [ [ @notification.id, @user.id ] ], access_checks
      assert_equal 1, capture_arguments.length
      assert_equal @notification.id,
        capture_arguments.first.fetch(:notification_id)
      assert_equal @subscription.id,
        capture_arguments.first.fetch(:subscription_id)
    end

    test "disabled mode preserves network delivery and loads configured VAPID keys" do
      push_arguments = []
      private_key_reads = 0
      sender = lambda do |**arguments|
        push_arguments << arguments
      end
      private_key = lambda do
        private_key_reads += 1
        "test-private-key"
      end
      unexpected_capture = lambda do |**|
        flunk "disabled Developer Mode must not capture Web Push"
      end

      result = with_developer_mode(enabled: false) do
        with_singleton_method(
          Mcweb::DeveloperModeCapture,
          :capture_web_push!,
          unexpected_capture
        ) do
          with_singleton_method(Community::VapidKeys, :public_key, -> { "test-public-key" }) do
            with_singleton_method(Community::VapidKeys, :private_key, private_key) do
              with_singleton_method(WebPush, :payload_send, sender) do
                Community::DeliverWebPush.call(notification: @notification)
              end
            end
          end
        end
      end

      assert_predicate result, :success?
      assert_nil result.value
      assert_equal 1, private_key_reads
      assert_equal 1, push_arguments.length
      assert_equal @subscription.endpoint, push_arguments.first.fetch(:endpoint)
      assert_equal @subscription.p256dh_key, push_arguments.first.fetch(:p256dh)
      assert_equal @subscription.auth_key, push_arguments.first.fetch(:auth)
      assert_equal "test-private-key",
        push_arguments.first.dig(:vapid, :private_key)
    end

    test "capture mode skips local capture when content access is revoked" do
      access_checks = []
      denied = ->(notification:, user:) do
        access_checks << [ notification.id, user.id ]
        false
      end
      unexpected_capture = lambda do |**|
        flunk "access-revoked notifications must not be captured"
      end

      result = with_developer_mode(enabled: true) do
        with_singleton_method(Community::NotificationAccess, :visible?, denied) do
          with_singleton_method(
            Mcweb::DeveloperModeCapture,
            :capture_web_push!,
            unexpected_capture
          ) do
            without_real_web_push do
              Community::DeliverWebPush.call(notification: @notification)
            end
          end
        end
      end

      assert_predicate result, :success?
      assert_equal true, result.value.fetch(:skipped)
      assert_equal [ [ @notification.id, @user.id ] ], access_checks
    end

    private

    def with_developer_mode(enabled:, &block)
      settings = Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: enabled,
            preset: "unrestricted"
          }
        },
        environment: {}
      )
      previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      block.call
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
    end

    def without_real_web_push(&block)
      unexpected_network = lambda do |**|
        flunk "capture mode must not call the WebPush network adapter"
      end
      unexpected_vapid = lambda do
        flunk "capture mode must not load VAPID keys"
      end

      with_singleton_method(WebPush, :payload_send, unexpected_network) do
        with_singleton_method(Community::VapidKeys, :public_key, unexpected_vapid) do
          with_singleton_method(Community::VapidKeys, :private_key, unexpected_vapid, &block)
        end
      end
    end

    def with_singleton_method(object, method_name, replacement)
      singleton = object.singleton_class
      original = object.method(method_name)
      singleton.send(:define_method, method_name, replacement)
      yield
    ensure
      singleton&.send(:define_method, method_name, original)
    end
  end
end
