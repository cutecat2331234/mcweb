# frozen_string_literal: true

require "test_helper"

module Community
  class DeveloperModeAntiSpamTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @other = create_user
      @category = Community::Category.create!(
        name: "Developer gates",
        slug: "developer-gates-#{SecureRandom.hex(4)}"
      )
      @section = Community::Section.create!(
        category: @category,
        name: "Developer gates",
        slug: "developer-gates-#{SecureRandom.hex(4)}",
        position: 0,
        min_trust_level_create: 4,
        min_trust_level_reply: 4
      )
    end

    test "unrestricted mode bypasses trust gates without changing the recorded level" do
      SiteSetting.set("forum.min_trust_level_pm", "4")
      SiteSetting.set("forum.min_trust_level_reaction", "4")

      with_developer_mode do
        assert_equal 0, Community::TrustLevel.level_for(@user)
        assert Community::TrustLevel.can_send_pm?(@user)
        assert Community::TrustLevel.can_post_links?(@user)
        assert Community::TrustLevel.can_upload_images?(@user)
        assert Community::TrustLevel.can_upload_attachments?(@user)
        assert Community::TrustLevel.can_react?(@user)
        assert @section.trust_allowed?(@user, :create_topic)
        refute @section.trust_allowed?(nil, :create_topic)
      end
    end

    test "topic and reply cooldown duplicate and slow-mode gates are bypassed" do
      with_developer_mode do
        first = create_topic(title: "Repeated title")
        second = create_topic(title: "Repeated title")

        assert first.success?, first.error
        assert second.success?, second.error

        topic = first.value
        topic.update!(slow_mode_seconds: 3_600)
        assert_no_difference("RateLimitCounter.count") do
          first_reply = Community::CreatePost.call(
            user: @user,
            topic: topic,
            body: "Repeated reply body",
            ip_address: "127.0.0.1"
          )
          second_reply = Community::CreatePost.call(
            user: @user,
            topic: topic,
            body: "Repeated reply body",
            ip_address: "127.0.0.1"
          )

          assert first_reply.success?, first_reply.error
          assert second_reply.success?, second_reply.error
        end
      end
    end

    test "approval and bump cooldown gates are bypassed" do
      SiteSetting.set("forum.require_post_approval_below_tl", "4")
      SiteSetting.set("forum.bump_cooldown_hours", "24")
      moderator = create_user
      grant_permission(moderator, "forum.topics.lock")
      topic = Community::Topic.create!(
        section: @section,
        user: moderator,
        title: "Developer bump",
        status: "published",
        last_posted_at: 1.hour.ago,
        last_post_user: moderator,
        bumped_at: 1.hour.ago
      )

      with_developer_mode do
        refute Community::RequiresPostApproval.required_for?(user: @user)
        result = Community::ModerateTopic.call(
          user: moderator,
          topic: topic,
          action: "bump"
        )

        assert result.success?, result.error
        assert topic.reload.bumped_at > 1.minute.ago
      end
    end

    test "permissions blocks and account sanctions remain enforced" do
      @section.update!(permissions: { "create_topic" => [ "special_role" ] })
      Community::UserBlock.create!(blocker: @other, blocked: @user)
      banned = create_user(status: "banned")
      topic = Community::Topic.create!(
        section: @section,
        user: @other,
        title: "Sanctioned reply",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @other
      )

      with_developer_mode do
        refute @section.allowed?(@user, :create_topic)
        refute Community::ProfileWallPolicy.can_post?(
          author: @user,
          profile_user: @other
        )

        result = Community::CreatePost.call(
          user: banned,
          topic: topic,
          body: "This must stay blocked",
          ip_address: "127.0.0.1"
        )
        assert result.failure?
        assert result.error.present?
        assert_predicate banned.reload, :banned?
      end
    end

    private

    def create_topic(title:)
      Community::CreateTopic.call(
        user: @user,
        section: @section,
        title: title,
        body: "Developer mode topic body",
        ip_address: "127.0.0.1"
      )
    end

    def with_developer_mode
      settings = Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: true,
            preset: "unrestricted"
          }
        },
        environment: {}
      )
      previous = Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      yield
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous)
    end
  end
end
