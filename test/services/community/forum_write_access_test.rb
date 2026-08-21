# frozen_string_literal: true

require "test_helper"

module Community
  class ForumWriteAccessTest < ActiveSupport::TestCase
    setup do
      suffix = SecureRandom.hex(4)
      @category = Community::Category.create!(
        name: "Forum writes #{suffix}",
        slug: "forum-writes-#{suffix}"
      )
      @section = Community::Section.create!(
        category: @category,
        name: "Forum writes",
        slug: "forum-writes-#{suffix}",
        position: 0
      )
      @author = create_user
      @member = create_user
      @moderator = create_user
      Community::SectionModerator.create!(section: @section, user: @moderator)
      @topic = create_topic(section: @section, user: @author)
      @opening_post = create_post(topic: @topic, user: @author, floor_number: 1)
    end

    test "new replies and reply drafts reject closed topic states for every visible actor" do
      cases = [
        [ { status: "draft" }, @author ],
        [ { status: "hidden" }, @author ],
        [ { status: "hidden" }, @moderator ],
        [ { archived_at: Time.current }, @author ],
        [ { archived_at: Time.current }, @moderator ],
        [ { locked: true }, @author ],
        [ { locked: true }, @moderator ]
      ]

      cases.each_with_index do |(attributes, actor), index|
        @topic.update!(status: "published", archived_at: nil, locked: false)
        @topic.update!(attributes)

        post_result = nil
        assert_no_difference -> { Community::Post.count } do
          post_result = Community::CreatePost.call(
            user: actor,
            topic: @topic,
            body: "Blocked reply #{index}",
            skip_interval_check: true
          )
        end
        assert_predicate post_result, :failure?

        draft_result = nil
        assert_no_difference -> { Community::ReplyDraft.count } do
          draft_result = Community::SaveReplyDraft.call(
            user: actor,
            topic: @topic,
            body: "Blocked draft #{index}"
          )
        end
        assert_predicate draft_result, :failure?
      end
    end

    test "reply drafts enforce section reply permissions" do
      @section.update!(permissions: { "reply" => [ "forum.private.reply" ] })

      result = nil
      assert_no_difference -> { Community::ReplyDraft.count } do
        result = Community::SaveReplyDraft.call(
          user: @member,
          topic: @topic,
          body: "Permission bypass draft"
        )
      end

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.you_are_not_allowed_to_reply_in_this_section"),
        result.error
    end

    test "published unlisted topics remain directly readable and replyable" do
      @topic.update!(unlisted: true)

      assert Community::ForumAccess.topic_visible?(topic: @topic, user: @member)
      post_result = Community::CreatePost.call(
        user: @member,
        topic: @topic,
        body: "Direct link reply",
        skip_interval_check: true
      )
      assert_predicate post_result, :success?

      draft_result = Community::SaveReplyDraft.call(
        user: @member,
        topic: @topic,
        body: "Direct link draft"
      )
      assert_predicate draft_result, :success?
    end

    test "quoted and parent posts must still be readable and not soft deleted" do
      hidden_parent = create_post(
        topic: @topic,
        user: @author,
        floor_number: 2,
        status: "hidden",
        body: "Hidden parent"
      )
      deleted_reference = create_post(
        topic: @topic,
        user: @author,
        floor_number: 3,
        body: "Deleted reference"
      )
      deleted_reference.soft_delete!

      restricted_section = Community::Section.create!(
        category: @category,
        name: "Restricted quote",
        slug: "restricted-quote-#{SecureRandom.hex(4)}",
        position: 1,
        permissions: { "view" => [ "forum.private.quote" ] }
      )
      restricted_topic = create_topic(section: restricted_section, user: @author)
      restricted_post = create_post(topic: restricted_topic, user: @author, floor_number: 1)

      attempts = [
        { parent_post: hidden_parent },
        { parent_post: deleted_reference },
        { quoted_post: deleted_reference },
        { quoted_post: restricted_post }
      ]

      attempts.each_with_index do |reference, index|
        result = nil
        assert_no_difference -> { Community::Post.count } do
          result = Community::CreatePost.call(
            user: @member,
            topic: @topic,
            body: "Rejected reference #{index}",
            skip_interval_check: true,
            **reference
          )
        end
        assert_predicate result, :failure?
      end

      assert_not Community::PostAccess.readable?(post: deleted_reference, user: @author)
    end

    test "archived topics are read only for authors and section moderators" do
      @opening_post.edit_body!("Current archived body", editor: @author)
      edit = @opening_post.edits.order(:id).last
      @topic.update!(archived_at: Time.current)

      [ @author, @moderator ].each do |actor|
        edit_result = Community::EditPost.call(
          user: actor,
          post: @opening_post,
          body: "Archived mutation by #{actor.id}",
          expected_revision: @opening_post.revision
        )
        assert_predicate edit_result, :failure?
        assert_equal I18n.t("mcweb.services.errors.post_not_available"),
          edit_result.error

        restore_result = Community::RestorePostEdit.call(user: actor, edit: edit)
        assert_predicate restore_result, :failure?
        assert_equal I18n.t("mcweb.services.errors.post_not_available"),
          restore_result.error
      end

      topic_result = Community::EditTopic.call(
        user: @author,
        topic: @topic,
        title: "Archived title mutation"
      )
      assert_predicate topic_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.this_topic_is_archived"),
        topic_result.error

      poll_result = Community::EditTopicPoll.call(
        user: @author,
        topic: @topic,
        poll_question: "Archived poll mutation?"
      )
      assert_predicate poll_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.this_topic_is_archived"),
        poll_result.error

      assert_equal "Current archived body", @opening_post.reload.body
      assert_not_equal "Archived title mutation", @topic.reload.title
    end

    test "section moderators retain edit and restore access in hidden topics" do
      @topic.update!(status: "hidden")
      hidden_post = create_post(
        topic: @topic,
        user: @author,
        floor_number: 2,
        status: "hidden",
        body: "Hidden moderated body"
      )
      pending_post = create_post(
        topic: @topic,
        user: @author,
        floor_number: 3,
        status: "pending_approval",
        body: "Pending moderated body"
      )
      @opening_post.edit_body!("Body with revision", editor: @author)
      edit = @opening_post.edits.order(:id).last

      assert Community::PostAccess.readable?(post: hidden_post, user: @moderator)
      assert Community::PostAccess.readable?(post: pending_post, user: @moderator)

      hidden_result = Community::EditPost.call(
        user: @moderator,
        post: hidden_post,
        body: "Edited hidden body",
        expected_revision: hidden_post.revision
      )
      assert_predicate hidden_result, :success?

      pending_result = Community::EditPost.call(
        user: @moderator,
        post: pending_post,
        body: "Edited pending body",
        expected_revision: pending_post.revision
      )
      assert_predicate pending_result, :success?

      restore_result = Community::RestorePostEdit.call(user: @moderator, edit: edit)
      assert_predicate restore_result, :success?
      assert_equal edit.body_before, @opening_post.reload.body
    end

    test "soft deleted posts cannot be edited or restored through retained objects" do
      @opening_post.edit_body!("Edited before deletion", editor: @author)
      edit = @opening_post.edits.order(:id).last
      @opening_post.soft_delete!

      edit_result = Community::EditPost.call(
        user: @author,
        post: @opening_post,
        body: "Edit after deletion",
        expected_revision: @opening_post.revision
      )
      assert_predicate edit_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.post_not_available"),
        edit_result.error

      restore_result = Community::RestorePostEdit.call(user: @moderator, edit: edit)
      assert_predicate restore_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.post_not_available"),
        restore_result.error
    end

    test "post editing and revision restore require an authenticated actor" do
      @opening_post.edit_body!("Wiki revision", editor: @author)
      edit = @opening_post.edits.order(:id).last
      @topic.update!(wiki: true)

      assert_not Community::PostAccess.editable?(post: @opening_post, user: nil)

      restore_result = Community::RestorePostEdit.call(user: nil, edit: edit)
      assert_predicate restore_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.post_not_available"),
        restore_result.error
      assert_equal "Wiki revision", @opening_post.reload.body
    end

    test "poll voting and revocation require section visibility" do
      _section, topic, = create_restricted_topic
      poll = Community::Poll.create!(
        topic: topic,
        question: "Restricted poll?",
        options: %w[Yes No]
      )
      poll.votes.create!(user: @author, option_index: 0)

      assert_not Community::PollParticipation.allowed?(user: @author, poll: poll)
      assert_not Community::PollParticipation.allowed?(user: nil, poll: poll)

      vote_result = nil
      assert_no_difference -> { poll.votes.count } do
        vote_result = Community::VotePoll.call(
          user: @author,
          poll: poll,
          option_index: 1
        )
      end
      assert_predicate vote_result, :failure?

      revoke_result = nil
      assert_no_difference -> { poll.votes.count } do
        revoke_result = Community::RevokePollVote.call(user: @author, poll: poll)
      end
      assert_predicate revoke_result, :failure?
      assert poll.votes.exists?(user: @author, option_index: 0)
    end

    test "direct owner topic and poll mutations reject a restricted section" do
      _section, topic, post = create_restricted_topic
      topic.update!(solved_post: post)
      poll = Community::Poll.create!(
        topic: topic,
        question: "Original restricted poll?",
        options: %w[Yes No]
      )

      unsolve_result = Community::UnsolveTopic.call(user: @author, topic: topic)
      assert_predicate unsolve_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        unsolve_result.error
      assert_equal post.id, topic.reload.solved_post_id

      close_result = nil
      assert_no_difference -> { Community::Post.count } do
        close_result = Community::CloseOwnTopic.call(
          user: @author,
          topic: topic,
          action: "close"
        )
      end
      assert_predicate close_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        close_result.error
      assert_not_predicate topic.reload, :locked?

      edit_poll_result = Community::EditTopicPoll.call(
        user: @author,
        topic: topic,
        poll_question: "Mutated restricted poll?"
      )
      assert_predicate edit_poll_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        edit_poll_result.error
      assert_equal "Original restricted poll?", poll.reload.question

      close_poll_result = Community::ClosePoll.call(user: @author, poll: poll)
      assert_predicate close_poll_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"),
        close_poll_result.error
      assert_predicate poll.reload, :open?
    end

    test "author deletion respects section visibility while moderator governance remains available" do
      section, topic, = create_restricted_topic
      author_reply = create_post(
        topic: topic,
        user: @author,
        floor_number: 2,
        body: "Restricted author reply"
      )

      author_result = Community::DeletePost.call(actor: @author, post: author_reply)
      assert_predicate author_result, :failure?
      assert_nil author_reply.reload.deleted_at

      moderator_reply = create_post(
        topic: topic,
        user: @author,
        floor_number: 3,
        body: "Restricted moderator reply"
      )
      Community::SectionModerator.create!(section: section, user: @moderator)

      moderator_result = Community::DeletePost.call(actor: @moderator, post: moderator_reply)
      assert_predicate moderator_result, :success?
      assert_not_nil moderator_reply.reload.deleted_at
    end

    test "nested topic metadata and attachment mutators reject a restricted section" do
      _section, topic, post = create_restricted_topic
      tag_name = "restricted-tag-#{SecureRandom.hex(4)}"

      tag_result = Community::SyncTopicTags.call(
        topic: topic,
        tag_names: [ tag_name ],
        user: @author
      )
      assert_predicate tag_result, :failure?
      assert_empty topic.reload.tags
      assert_not Community::Tag.exists?(name: tag_name)

      hashtag_result = Community::ProcessHashtags.call(
        topic: topic,
        body: "A #restricted_hashtag must not mutate",
        user: @author
      )
      assert_predicate hashtag_result, :failure?
      assert_empty topic.reload.tags

      definition = Community::TopicFieldDefinition.create!(
        key: "restricted_field_#{SecureRandom.hex(4)}",
        label: "Restricted field",
        field_type: "text",
        display_location: "before_message",
        active: true,
        editable_by_user: true
      )
      field_result = Community::SyncTopicFieldValues.call(
        topic: topic,
        user: @author,
        values: { definition.key => "leaked value" }
      )
      assert_predicate field_result, :failure?
      assert_not Community::TopicFieldValue.exists?(topic: topic, definition: definition)

      unlinked_attachment = Community::PostAttachment.create!(
        user: @author,
        filename: "restricted-unlinked.txt",
        content_type: "text/plain",
        byte_size: 4
      )
      link_result = Community::LinkPostAttachments.call(
        user: @author,
        post: post,
        attachment_ids: [ unlinked_attachment.id ]
      )
      assert_predicate link_result, :failure?
      assert_nil unlinked_attachment.reload.forum_post_id

      linked_attachment = Community::PostAttachment.create!(
        user: @author,
        post: post,
        filename: "restricted-linked.txt",
        content_type: "text/plain",
        byte_size: 4
      )
      sync_result = Community::SyncPostAttachments.call(
        user: @author,
        post: post,
        attachment_ids: []
      )
      assert_predicate sync_result, :failure?
      assert_equal post.id, linked_attachment.reload.forum_post_id
    end

    test "direct attachment synchronization respects the post edit window" do
      attachment = Community::PostAttachment.create!(
        user: @author,
        post: @opening_post,
        filename: "old-post.txt",
        content_type: "text/plain",
        byte_size: 4
      )
      @opening_post.update_column(:created_at, 2.days.ago)

      result = Community::SyncPostAttachments.call(
        user: @author,
        post: @opening_post,
        attachment_ids: []
      )

      assert_predicate result, :failure?
      assert_equal @opening_post.id, attachment.reload.forum_post_id
    end

    test "anonymous direct mutations fail cleanly for login required topics" do
      section = Community::Section.create!(
        category: @category,
        name: "Login required writes",
        slug: "login-required-writes-#{SecureRandom.hex(4)}",
        position: 5,
        login_required: true
      )
      topic = create_topic(section: section, user: @author)
      post = create_post(topic: topic, user: @author, floor_number: 1)
      topic.update!(solved_post: post)
      poll = Community::Poll.create!(
        topic: topic,
        question: "Members only?",
        options: %w[Yes No]
      )

      vote_result = Community::VotePoll.call(user: nil, poll: poll, option_index: 0)
      assert_predicate vote_result, :failure?

      unsolve_result = Community::UnsolveTopic.call(user: nil, topic: topic)
      assert_predicate unsolve_result, :failure?
      assert_equal post.id, topic.reload.solved_post_id

      close_result = Community::CloseOwnTopic.call(user: nil, topic: topic, action: "close")
      assert_predicate close_result, :failure?
      assert_not_predicate topic.reload, :locked?

      edit_poll_result = Community::EditTopicPoll.call(
        user: nil,
        topic: topic,
        poll_question: "Anonymous mutation?"
      )
      assert_predicate edit_poll_result, :failure?
      assert_equal "Members only?", poll.reload.question

      close_poll_result = Community::ClosePoll.call(user: nil, poll: poll)
      assert_predicate close_poll_result, :failure?
      assert_predicate poll.reload, :open?
    end

    test "archived topics reject ordinary polls reactions solutions and owner closing" do
      poll = Community::Poll.create!(
        topic: @topic,
        question: "Archive interaction?",
        options: %w[Yes No]
      )
      initial_vote = Community::VotePoll.call(
        user: @author,
        poll: poll,
        option_index: 0
      )
      assert_predicate initial_vote, :success?

      answer = create_post(
        topic: @topic,
        user: @member,
        floor_number: 2,
        body: "Potential solution"
      )
      @topic.update!(archived_at: Time.current, solved_post: answer)

      vote_result = Community::VotePoll.call(
        user: @moderator,
        poll: poll,
        option_index: 1
      )
      assert_predicate vote_result, :failure?
      assert_not poll.votes.exists?(user: @moderator)

      revoke_result = Community::RevokePollVote.call(user: @author, poll: poll)
      assert_predicate revoke_result, :failure?
      assert poll.votes.exists?(user: @author)

      reaction_result = nil
      assert_no_difference -> { Community::Reaction.count } do
        reaction_result = Community::ToggleReaction.call(
          user: @moderator,
          post: @opening_post,
          emoji: Community::ToggleReaction.allowed_emoji.first
        )
      end
      assert_predicate reaction_result, :failure?

      solve_result = Community::MarkTopicSolved.call(
        user: @author,
        topic: @topic,
        post: @opening_post
      )
      assert_predicate solve_result, :failure?
      assert_equal answer.id, @topic.reload.solved_post_id

      unsolve_result = Community::UnsolveTopic.call(user: @author, topic: @topic)
      assert_predicate unsolve_result, :failure?
      assert_equal answer.id, @topic.reload.solved_post_id

      close_result = nil
      assert_no_difference -> { Community::Post.count } do
        close_result = Community::CloseOwnTopic.call(
          user: @author,
          topic: @topic,
          action: "close"
        )
      end
      assert_predicate close_result, :failure?
      assert_not_predicate @topic.reload, :locked?
    end

    private

    def create_topic(section:, user:)
      Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: user,
        title: "Write boundary #{SecureRandom.hex(3)}",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: user,
        replies_count: 0
      )
    end

    def create_post(topic:, user:, floor_number:, status: "published", body: "Forum write body")
      Community::Post.create!(
        topic: topic,
        user: user,
        floor_number: floor_number,
        body: body,
        status: status
      )
    end

    def create_restricted_topic
      section = Community::Section.create!(
        category: @category,
        name: "Restricted writes",
        slug: "restricted-writes-#{SecureRandom.hex(4)}",
        position: 4,
        permissions: { "view" => [ "forum.restricted.write" ] }
      )
      topic = create_topic(section: section, user: @author)
      post = create_post(topic: topic, user: @author, floor_number: 1)
      [ section, topic, post ]
    end
  end
end
