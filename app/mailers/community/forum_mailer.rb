# frozen_string_literal: true

module Community
  class ForumMailer < ApplicationMailer
    include Rails.application.routes.url_helpers

    def topic_reply(user_id, topic_id, post_id)
      @user = User.find(user_id)
      return unless assign_visible_topic_and_post(topic_id, post_id)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.topic_reply")

      mail(to: @user.email, subject: "主题有新回复：#{@topic.title.truncate(60)}")
    end

    def private_message(user_id, conversation_id, message_id)
      @user = User.find(user_id)
      @conversation = Community::Conversation.find_by(id: conversation_id)
      @message = Community::Message.with_discarded.find_by(id: message_id)
      return unless Community::NotificationAccess.private_message_visible?(
        user: @user,
        conversation: @conversation,
        message: @message
      )

      @url = "#{root_url.chomp('/')}#{"/app/forum/conversations/#{@conversation.id}"}"
      assign_notification_unsubscribe("forum.private_message")

      mail(to: @user.email, subject: "来自 #{@message.user.username} 的私信")
    end

    def mention(user_id, topic_id, post_id)
      @user = User.find(user_id)
      return unless assign_visible_topic_and_post(topic_id, post_id)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @mention_unsubscribe_url = notification_type_unsubscribe_url_for(@user, "forum.mention")
      @notification_unsubscribe_url = @mention_unsubscribe_url

      mail(to: @user.email, subject: "#{@post.user.username} 在主题中提到了你")
    end

    def here(user_id, topic_id, post_id)
      @user = User.find(user_id)
      return unless assign_visible_topic_and_post(topic_id, post_id)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.here")

      mail(to: @user.email, subject: "#{@post.user.username} 在主题中 @here 提及了你")
    end

    def section_topic(user_id, topic_id)
      @user = User.find(user_id)
      @topic = find_topic_for_notification(topic_id)
      return unless forum_topic_visible?(@topic)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.section_topic")

      mail(to: @user.email, subject: "分区有新主题：#{@topic.title.truncate(60)}")
    end

    def tag_topic(user_id, topic_id, tag_ids)
      @user = User.find(user_id)
      @topic = find_topic_for_notification(topic_id)
      return unless forum_topic_visible?(@topic)

      tags = Community::NotificationAccess.tag_topic_tags(
        user: @user,
        topic: @topic,
        tag_ids: tag_ids
      )
      return if tags.empty?

      @tag_names = tags.map(&:name).join(", ")
      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.tag_topic")

      mail(to: @user.email, subject: "关注标签有新主题：#{@topic.title.truncate(60)}")
    end

    def followed_topic(user_id, topic_id)
      @user = User.find(user_id)
      @topic = find_topic_for_notification(topic_id)
      return unless forum_topic_visible?(@topic)

      @author = @topic.user
      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.followed_topic")

      mail(to: @user.email, subject: "#{@author.username} 发布了新主题")
    end

    def followed_reply(user_id, topic_id, post_id)
      @user = User.find(user_id)
      return unless assign_visible_topic_and_post(topic_id, post_id)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.followed_reply")

      mail(to: @user.email, subject: "#{@post.user.username} 回复了主题：#{@topic.title.truncate(60)}")
    end

    def digest(user_id, notification_ids)
      @user = User.find(user_id)
      notifications = Notification.where(id: notification_ids, user: @user).order(created_at: :desc)
      @notifications = visible_digest_notifications(notifications)
      return if @notifications.empty?

      @digest_sections = Community::GroupDigestNotifications.call(@notifications)
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @unread_notifications_url = "#{root_url.chomp('/')}#{forum_notifications_path(read: 'unread')}"
      @mention_unsubscribe_url = mention_unsubscribe_url_for(@user)
      @unsubscribe_url = "#{root_url.chomp('/')}#{forum_unsubscribe_forum_digest_path(token: Community::ForumDigestUnsubscribeToken.generate(@user))}"

      mail(to: @user.email, subject: "论坛摘要 — #{@notifications.count} 条新动态")
    end

    def saved_search_digest(saved_search_id, topic_ids)
      @search = Community::SavedSearch.find(saved_search_id)
      @user = @search.user
      return unless @user.session_eligible?

      @topics = Community::ForumAccess.listed_topic_scope(
        relation: Community::Topic.where(id: topic_ids),
        user: @user
      ).order(created_at: :desc)
      return if @topics.empty?

      @filter_labels = Community::SavedSearchFilterSummary.call(@search)
      @url = "#{root_url.chomp('/')}#{forum_search_path(search_url_for(@search))}"
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @unsubscribe_url = "#{root_url.chomp('/')}#{unsubscribe_forum_saved_searches_path(token: Community::SavedSearchUnsubscribeToken.generate(@search))}"
      @rss_url = "#{root_url.chomp('/')}#{Community::SavedSearchPresenter.rss_path(@search)}"

      mail(to: @user.email, subject: "保存的搜索有新结果：#{@search.name}")
    end

    def post_edited(user_id, topic_id, post_id)
      @user = User.find(user_id)
      return unless assign_visible_topic_and_post(topic_id, post_id)

      @editor = @post.user
      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.post_edited")

      mail(to: @user.email, subject: "帖子已编辑：#{@topic.title.truncate(60)}")
    end

    def bookmark_reminder(user_id, bookmark_id)
      @user = User.find(user_id)
      @bookmark = Community::Bookmark.find(bookmark_id)
      return unless @bookmark.user_id == @user.id

      @topic = Community::Topic.with_discarded.find_by(id: @bookmark.forum_topic_id)
      return unless forum_topic_visible?(@topic)
      if @bookmark.forum_post_id
        @post = Community::Post.with_discarded.find_by(id: @bookmark.forum_post_id)
        return unless @post&.forum_topic_id == @topic.id
        return unless forum_post_visible?(@post)
      end

      @url = if @post
               "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      else
               "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      end
      @note = @bookmark.note
      assign_notification_unsubscribe("forum.bookmark_reminder")

      mail(to: @user.email, subject: "书签提醒：#{@topic.title.truncate(60)}")
    end

    def user_warning(user_id, warning_id)
      @user = User.find(user_id)
      @warning = Community::UserWarning.find(warning_id)
      @url = "#{root_url.chomp('/')}#{"/app/forum/users/#{@user.username}"}"
      assign_notification_unsubscribe("forum.user_warning")
      mail(to: @user.email, subject: "社区警告通知")
    end

    def badge_earned(user_id, badge_id)
      @user = User.find(user_id)
      @badge = Community::Badge.find(badge_id)
      @url = "#{root_url.chomp('/')}#{forum_badge_path(@badge.slug)}"
      assign_notification_unsubscribe("forum.badge_earned")
      mail(to: @user.email, subject: "你获得了徽章：#{@badge.name}")
    end

    def topic_assigned(user_id, topic_id, actor_id)
      @user = User.find(user_id)
      @topic = find_topic_for_notification(topic_id)
      return unless forum_topic_visible?(@topic)

      @actor = User.find(actor_id)
      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.topic_assigned")
      mail(to: @user.email, subject: "主题已指派给你：#{@topic.title.truncate(60)}")
    end

    def trust_level_up(user_id, level, level_name)
      @user = User.find(user_id)
      @level = level
      @level_name = level_name
      @url = "#{root_url.chomp('/')}#{forum_user_path(@user.username)}"
      assign_notification_unsubscribe("forum.trust_level_up")
      mail(to: @user.email, subject: "信任等级提升：#{@level_name}")
    end

    def post_reaction(user_id, post_id, reactor_id, emoji)
      @user = User.find(user_id)
      @post = Community::Post.with_discarded.find_by(id: post_id)
      return unless forum_post_visible?(@post)

      @reactor = User.find(reactor_id)
      @emoji = emoji
      @topic = @post.topic

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.reaction")
      mail(to: @user.email, subject: "#{@reactor.username} 对你的帖子做出了反应 #{@emoji}")
    end

    def post_quoted(user_id, post_id, quoter_id, quoted_post_id)
      @user = User.find(user_id)
      @post = Community::Post.with_discarded.find_by(id: post_id)
      return unless forum_post_visible?(@post)

      @quoter = User.find(quoter_id)
      @quoted_post = Community::Post.with_discarded.find_by(id: quoted_post_id)
      @topic = @post.topic

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.quote")
      mail(to: @user.email, subject: "#{@quoter.username} 引用了你的帖子")
    end

    def topic_solved(user_id, topic_id, post_id, actor_id)
      @user = User.find(user_id)
      return unless assign_visible_topic_and_post(topic_id, post_id)

      @actor = User.find(actor_id)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.topic_solved")
      mail(to: @user.email, subject: "你的主题已标记为已解决")
    end

    def topic_invite(user_id, topic_id, inviter_id)
      @user = User.find(user_id)
      @topic = find_topic_for_notification(topic_id)
      return unless forum_topic_visible?(@topic)

      @inviter = User.find(inviter_id)
      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.topic_invite")

      mail(to: @user.email, subject: "#{@inviter.username} 邀请你关注主题")
    end

    def poll_closed(user_id, poll_id, actor_id)
      @user = User.find(user_id)
      @poll = Community::Poll.find(poll_id)
      @topic = @poll.topic
      @actor = User.find(actor_id)
      return unless forum_topic_visible?(@topic)

      @url = "#{root_url.chomp('/')}#{"/app/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.poll_closed")
      mail(to: @user.email, subject: "投票已关闭：#{@poll.question.truncate(60)}")
    end

    def notification_url_for(notification)
      Community::NotificationDestinationUrl.for(notification, root_url: root_url)
    end

    def mention_unsubscribe_url_for(user)
      notification_type_unsubscribe_url_for(user, "forum.mention")
    end

    def notification_type_unsubscribe_url_for(user, notification_type)
      token = Community::NotificationTypeUnsubscribeToken.generate(user, notification_type: notification_type)
      "#{root_url.chomp('/')}#{forum_unsubscribe_notification_type_path(token: token)}"
    end
    helper_method :notification_url_for, :mention_unsubscribe_url_for, :notification_type_unsubscribe_url_for

    def mail(headers = {}, &block)
      headers = headers.dup
      if !headers.key?(:reply_to) &&
          @user.present? &&
          @topic.present? &&
          Community::ForumEmailReplyAddress.issuable?(user: @user, topic: @topic)
        headers[:reply_to] = Community::ForumEmailReplyAddress.issue!(user: @user, topic: @topic)
      end

      super(headers, &block)
    end

  private

    def assign_visible_topic_and_post(topic_id, post_id)
      @topic = find_topic_for_notification(topic_id)
      @post = Community::Post.with_discarded.find_by(id: post_id)
      @topic.present? &&
        @post.present? &&
        @post.forum_topic_id == @topic.id &&
        forum_post_visible?(@post)
    end

    def find_topic_for_notification(public_id)
      Community::Topic.with_discarded.find_by(public_id: public_id)
    end

    def forum_topic_visible?(topic)
      Community::NotificationAccess.topic_visible_for_notification?(
        user: @user,
        topic: topic
      )
    end

    def forum_post_visible?(post)
      Community::NotificationAccess.post_visible_for_notification?(
        user: @user,
        post: post
      )
    end

    def visible_digest_notifications(notifications)
      Community::NotificationAccess.filter(
        notifications: notifications,
        user: @user
      )
    end

    def assign_notification_unsubscribe(notification_type)
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @notification_unsubscribe_url = notification_type_unsubscribe_url_for(@user, notification_type)
    end

    def search_url_for(search)
      Community::SavedSearchPresenter.url_params(search)
    end
  end
end
