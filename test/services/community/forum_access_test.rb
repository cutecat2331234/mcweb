# frozen_string_literal: true

require "test_helper"

module Community
  class ForumAccessTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    setup do
      suffix = SecureRandom.hex(4)
      @category = Community::Category.create!(
        name: "Access policy",
        slug: "access-policy-#{suffix}"
      )
      @public_section = Community::Section.create!(
        category: @category,
        name: "Public",
        slug: "access-public-#{suffix}",
        position: 0
      )
      @login_section = Community::Section.create!(
        category: @category,
        name: "Members",
        slug: "access-members-#{suffix}",
        position: 1,
        login_required: true
      )
      @restricted_section = Community::Section.create!(
        category: @category,
        name: "Restricted",
        slug: "access-restricted-#{suffix}",
        position: 2,
        permissions: { "view" => [ "forum.access_policy.view" ] }
      )
      @member = create_user
      @allowed_member = create_user
      grant_permission(@allowed_member, "forum.access_policy.view")
      @author = create_user
      @restricted_topic = create_topic(
        section: @restricted_section,
        title: "Restricted policy topic"
      )
      @restricted_post = Community::Post.create!(
        topic: @restricted_topic,
        user: @author,
        floor_number: 1,
        body: "Restricted policy body",
        status: "published"
      )
    end

    test "section policy composes login and view permission rules" do
      assert Community::SectionAccess.view?(section: @public_section, user: nil)
      assert_not Community::SectionAccess.view?(section: @login_section, user: nil)
      assert Community::SectionAccess.view?(section: @login_section, user: @member)
      assert_not Community::SectionAccess.view?(section: @restricted_section, user: nil)
      assert_not Community::SectionAccess.view?(section: @restricted_section, user: @member)
      assert Community::SectionAccess.view?(section: @restricted_section, user: @allowed_member)
    end

    test "section and topic scopes exclude restricted records without permission" do
      visible_sections = Community::SectionAccess.scope(
        relation: Community::Section.where(id: [ @public_section.id, @restricted_section.id ]),
        user: @member
      )
      assert_includes visible_sections, @public_section
      assert_not_includes visible_sections, @restricted_section

      visible_topics = Community::ForumAccess.topic_scope(
        relation: Community::Topic.where(id: @restricted_topic.id),
        user: @member
      )
      assert_empty visible_topics

      allowed_topics = Community::ForumAccess.topic_scope(
        relation: Community::Topic.where(id: @restricted_topic.id),
        user: @allowed_member
      )
      assert_equal [ @restricted_topic.id ], allowed_topics.pluck(:id)
    end

    test "topic and post predicates enforce the same section boundary" do
      assert_not Community::ForumAccess.topic_visible?(topic: @restricted_topic, user: @member)
      assert_not Community::ForumAccess.post_visible?(post: @restricted_post, user: @member)
      assert_not Community::PostAccess.readable?(post: @restricted_post, user: @member)

      assert Community::ForumAccess.topic_visible?(topic: @restricted_topic, user: @allowed_member)
      assert Community::ForumAccess.post_visible?(post: @restricted_post, user: @allowed_member)
      assert Community::PostAccess.readable?(post: @restricted_post, user: @allowed_member)
    end

    test "notification recipients and digests recheck topic visibility" do
      recipients = Community::FilterNotificationRecipients.call(
        actor_id: @author.id,
        recipient_ids: [ @member.id, @allowed_member.id ],
        topic: @restricted_topic
      )
      assert_predicate recipients, :success?
      assert_equal [ @allowed_member.id ], recipients.value

      @member.update!(
        forum_digest_frequency: "daily",
        forum_digest_last_sent_at: 2.days.ago
      )
      notification = @member.notifications.create!(
        notification_type: "forum.topic_reply",
        title: "Restricted digest title",
        body: "Restricted digest body",
        metadata: { topic_id: @restricted_topic.public_id }
      )

      assert_no_enqueued_jobs only: MailDeliveryJob do
        digest = Community::SendForumDigest.call(user: @member)
        assert_predicate digest, :success?
        assert digest.value[:skipped]
      end
      assert_not notification.reload.read?

      assert_no_emails do
        Community::ForumMailer
          .topic_reply(@member.id, @restricted_topic.public_id, @restricted_post.id)
          .deliver_now
        Community::ForumMailer
          .digest(@member.id, [ notification.id ])
          .deliver_now
      end
    end

    test "listed scopes exclude moderation states whispers unlisted and archived content" do
      listed_topic = create_topic(section: @public_section, title: "Listed topic")
      regular = Community::Post.create!(
        topic: listed_topic,
        user: @author,
        floor_number: 1,
        body: "Public aggregate body",
        status: "published"
      )
      whisper = Community::Post.create!(
        topic: listed_topic,
        user: @author,
        floor_number: 2,
        body: "Whisper aggregate body",
        status: "published",
        post_type: "whisper"
      )
      Community::Post.create!(
        topic: listed_topic,
        user: @author,
        floor_number: 3,
        body: "Pending aggregate body",
        status: "pending_approval"
      )
      Community::Post.create!(
        topic: listed_topic,
        user: @author,
        floor_number: 4,
        body: "Hidden aggregate body",
        status: "hidden"
      )
      unlisted = create_topic(section: @public_section, title: "Unlisted aggregate topic")
      unlisted.update!(unlisted: true)
      archived = create_topic(section: @public_section, title: "Archived aggregate topic")
      archived.update!(archived_at: Time.current)

      topics = Community::ForumAccess.listed_topic_scope(
        relation: Community::Topic.where(id: [ listed_topic.id, unlisted.id, archived.id ]),
        user: @member
      )
      posts = Community::ForumAccess.listed_post_scope(
        relation: listed_topic.posts,
        user: @member
      )

      assert_equal [ listed_topic.id ], topics.pluck(:id)
      assert_equal [ regular.id ], posts.pluck(:id)

      moderator = create_user
      Community::SectionModerator.create!(section: @public_section, user: moderator)
      assert Community::ForumAccess.post_visible?(post: whisper, user: moderator)
      assert_not Community::ForumAccess.listed_post_visible?(post: whisper, user: moderator)
      assert_equal [ regular.id ], Community::ForumAccess.listed_post_scope(
        relation: listed_topic.posts,
        user: moderator
      ).pluck(:id)
    end

    test "anonymous oneboxes do not expose restricted forum resources or staff tags" do
      topic_result = Community::FetchTopicOnebox.call(
        url: "/app/forum/topics/#{@restricted_topic.public_id}"
      )
      section_result = Community::FetchSectionOnebox.call(
        url: "/forum/sections/#{@restricted_section.slug}"
      )

      assert_predicate topic_result, :success?
      assert_nil topic_result.value
      assert_predicate section_result, :success?
      assert_nil section_result.value

      private_category = Community::Category.create!(
        name: "Private onebox category",
        slug: "private-onebox-#{SecureRandom.hex(4)}"
      )
      Community::Section.create!(
        category: private_category,
        name: "Private onebox section",
        slug: "private-onebox-section-#{SecureRandom.hex(4)}",
        position: 0,
        permissions: { "view" => [ "forum.private_onebox.view" ] }
      )
      category_result = Community::FetchCategoryOnebox.call(
        url: "/forum/categories/#{private_category.slug}"
      )
      assert_predicate category_result, :success?
      assert_nil category_result.value

      staff_tag = Community::Tag.create!(
        name: "Staff onebox tag",
        slug: "staff-onebox-#{SecureRandom.hex(4)}",
        staff_only: true
      )
      tag_result = Community::FetchTagOnebox.call(
        url: "/forum/tags/#{staff_tag.slug}"
      )
      assert_predicate tag_result, :success?
      assert_nil tag_result.value
      assert_not_includes Community::Tag.usable_by(nil), staff_tag

      public_alias = Community::Tag.create!(
        name: "Public-looking alias",
        slug: "public-alias-#{SecureRandom.hex(4)}",
        canonical_tag: staff_tag
      )
      assert_nil Community::Tag.resolve_by_slug_for(public_alias.slug, user: nil)
      alias_result = Community::FetchTagOnebox.call(
        url: "/forum/tags/#{public_alias.slug}"
      )
      assert_predicate alias_result, :success?
      assert_nil alias_result.value
    end

    test "topic and post creation reject an unreadable section without writing" do
      topic_result = nil
      assert_no_difference -> { Community::Topic.count } do
        topic_result = Community::CreateTopic.call(
          user: @member,
          section: @restricted_section,
          title: "Must not be created",
          body: "Hidden write attempt",
          ip_address: "127.0.0.1"
        )
      end
      assert topic_result.failure?
      assert_equal I18n.t("mcweb.services.errors.section_not_available"),
        topic_result.error

      post_result = nil
      assert_no_difference -> { Community::Post.count } do
        post_result = Community::CreatePost.call(
          user: @member,
          topic: @restricted_topic,
          body: "Must not be created",
          ip_address: "127.0.0.1",
          skip_interval_check: true
        )
      end
      assert post_result.failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        post_result.error
    end

    test "draft and scheduled write paths reject an unreadable section" do
      draft_result = nil
      assert_no_difference -> { Community::Topic.count } do
        draft_result = Community::SaveTopicDraft.call(
          user: @member,
          section: @restricted_section,
          title: "Hidden draft",
          body: "Must not be saved"
        )
      end
      assert draft_result.failure?
      assert_equal I18n.t("mcweb.services.errors.section_not_available"),
        draft_result.error

      schedule_result = nil
      assert_no_difference -> { Community::Topic.count } do
        schedule_result = Community::ScheduleTopic.call(
          user: @member,
          section: @restricted_section,
          title: "Hidden scheduled topic",
          body: "Must not be scheduled",
          scheduled_at: 1.hour.from_now,
          ip_address: "127.0.0.1"
        )
      end
      assert schedule_result.failure?
      assert_equal I18n.t("mcweb.services.errors.section_not_available"),
        schedule_result.error
    end

    test "publish and edit paths stop when section visibility has been revoked" do
      draft = create_topic(section: @restricted_section, title: "Restricted draft")
      draft.update!(status: "draft")
      draft_post = Community::Post.create!(
        topic: draft,
        user: @member,
        floor_number: 1,
        body: "Draft body",
        status: "published"
      )

      publish_result = Community::PublishTopicDraft.call(user: @member, topic: draft)
      assert publish_result.failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        publish_result.error
      assert_predicate draft.reload, :draft?
      assert_predicate draft_post.reload, :published?

      draft.update!(scheduled_at: 1.minute.ago)
      scheduled_result = Community::PublishScheduledTopic.call(topic: draft)
      assert scheduled_result.failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        scheduled_result.error
      assert_predicate draft.reload, :draft?

      edit_result = Community::EditTopic.call(
        user: @member,
        topic: @restricted_topic,
        title: "Leaked edit"
      )
      assert edit_result.failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        edit_result.error
      assert_equal "Restricted policy topic", @restricted_topic.reload.title
    end

    private

    def create_topic(section:, title:)
      Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: @author,
        title: title,
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
    end
  end
end
