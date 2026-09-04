# frozen_string_literal: true

require "test_helper"

module Community
  class AccountClosureWriteFenceTest < ActiveSupport::TestCase
    setup do
      suffix = SecureRandom.hex(5)
      category = Community::Category.create!(
        name: "Closure write fence #{suffix}",
        slug: "closure-write-fence-#{suffix}"
      )
      @section = Community::Section.create!(
        category:,
        name: "Closure write fence",
        slug: "closure-write-fence-#{suffix}",
        position: 0
      )
      @user = create_user
      @user.update!(forum_trust_level_override: 1)
      @other = create_user
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @other,
        title: "Existing topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @other,
        replies_count: 0
      )
      @opening_post = Community::Post.create!(
        topic: @topic,
        user: @other,
        floor_number: 1,
        body: "Existing opening post",
        status: "published"
      )
      @conversation = Community::Conversation.create!(title: "Closure write fence")
      Community::ConversationParticipant.create!(conversation: @conversation, user: @user)
      Community::ConversationParticipant.create!(conversation: @conversation, user: @other)
      @profile_post = Community::ProfilePost.create!(
        profile_user: @other,
        author: @other,
        body: "Existing profile wall post",
        status: "published"
      )
      @user.update!(status: "deleted", deleted_at: Time.current)
    end

    test "closed accounts cannot create conversation openers scheduled topics or action posts" do
      results = []
      assert_no_difference -> { Community::Message.count } do
        results << Community::CreateConversation.call(
          sender: @user,
          recipient_username: @other.username,
          body: "Late conversation opener"
        )
        results << Community::CreateGroupConversation.call(
          sender: @user,
          title: "Late group",
          recipient_usernames: [ @other.username ],
          body: "Late group opener"
        )
      end

      assert_no_difference -> { Community::Topic.count } do
        results << Community::ScheduleTopic.call(
          user: @user,
          section: @section,
          title: "Late scheduled topic",
          body: "Must not cross the closure boundary",
          scheduled_at: 1.day.from_now
        )
        results << Community::CreateTopicFromPost.call(
          user: @user,
          post: @opening_post,
          title: "Late fork"
        )
      end

      assert_no_difference -> { Community::Post.count } do
        results << Community::CreateSmallActionPost.call(
          topic: @topic,
          actor: @user,
          body: "Late action"
        )
      end

      results.each do |result|
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.account_deleted"), result.error
      end
    end

    test "closed accounts cannot create topics posts or private messages" do
      topic_result = nil
      assert_no_difference -> { Community::Topic.count } do
        topic_result = Community::CreateTopic.call(
          user: @user,
          section: @section,
          title: "Late topic",
          body: "Must not cross the closure boundary"
        )
      end

      post_result = nil
      assert_no_difference -> { Community::Post.count } do
        post_result = Community::CreatePost.call(
          user: @user,
          topic: @topic,
          body: "Late reply",
          skip_interval_check: true
        )
      end

      message_result = nil
      assert_no_difference -> { Community::Message.count } do
        message_result = Community::SendMessage.call(
          user: @user,
          conversation: @conversation,
          body: "Late private message"
        )
      end


      profile_post_result = nil
      assert_no_difference -> { Community::ProfilePost.count } do
        profile_post_result = Community::CreateProfilePost.call(
          author: @user,
          profile_user: @profile_post.profile_user,
          body: "Late profile post"
        )
      end

      profile_comment_result = nil
      assert_no_difference -> { Community::ProfilePostComment.count } do
        profile_comment_result = Community::CreateProfilePostComment.call(
          author: @user,
          profile_post: @profile_post,
          body: "Late profile comment"
        )
      end

      [
        topic_result,
        post_result,
        message_result,
        profile_post_result,
        profile_comment_result
      ].each do |result|
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.account_deleted"), result.error
      end
    end

    test "write services lock the identity row before inserting authored content" do
      assertions = {
        "app/services/community/create_topic.rb" => "Community::Topic.create!",
        "app/services/community/create_post.rb" => "Community::Post.create!",
        "app/services/community/send_message.rb" => "@conversation.messages.create!",
        "app/services/community/create_profile_post.rb" => "Community::ProfilePost.create!",
        "app/services/community/create_profile_post_comment.rb" =>
          "@profile_post.comments.create!",
        "app/services/community/create_conversation.rb" => "conversation.messages.create!",
        "app/services/community/schedule_topic.rb" => "Community::Topic.create!",
        "app/services/community/save_topic_draft.rb" => "draft.save!",
        "app/services/community/publish_topic_draft.rb" => "@topic.update!",
        "app/services/community/publish_scheduled_topic.rb" => "@topic.update!",
        "app/services/community/create_topic_from_post.rb" => "Community::Topic.create!",
        "app/services/community/create_small_action_post.rb" => "Community::Post.create!",
        "app/services/community/edit_post.rb" => "@post.update!",
        "app/services/community/restore_post_edit.rb" => "@post.edit_body!",
        "app/services/community/edit_message.rb" => "@message.update!",
        "app/services/community/edit_profile_wall_item.rb" => "@item.update!"
      }

      assertions.each do |path, insertion|
        source = Rails.root.join(path).read
        lock_position = source.index("User.lock.find")
        insert_position = source.index(insertion)

        assert lock_position, "#{path} must lock the author identity row"
        assert insert_position, "#{path} must retain its content insertion"
        assert_operator lock_position, :<, insert_position,
                        "#{path} must lock and revalidate the user before insertion"
      end

      edit_topic_source = Rails.root.join(
        "app/services/community/edit_topic.rb"
      ).read
      edit_topic_lock_position = edit_topic_source.index(
        "Identity::UserMutationLock.with_users"
      )
      edit_topic_update_position = edit_topic_source.index("@topic.update!")
      assert edit_topic_lock_position
      assert edit_topic_update_position
      assert_operator edit_topic_lock_position, :<, edit_topic_update_position


      group_source = Rails.root.join(
        "app/services/community/create_group_conversation.rb"
      ).read
      group_lock_position = group_source.index("Identity::UserMutationLock.with_users")
      group_state_position = group_source.index("account_write_access_result")
      group_insert_position = group_source.index("conversation.messages.create!")
      assert group_lock_position
      assert group_state_position
      assert group_insert_position
      assert_operator group_lock_position, :<, group_state_position
      assert_operator group_state_position, :<, group_insert_position
    end
  end
end
