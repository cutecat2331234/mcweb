# frozen_string_literal: true

module Community
  class ForumMailer < ApplicationMailer
    include Rails.application.routes.url_helpers

    def topic_reply(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.topic_reply")

      mail(to: @user.email, subject: "主题有新回复：#{@topic.title.truncate(60)}")
    end

    def private_message(user_id, conversation_id, message_id)
      @user = User.find(user_id)
      @conversation = Community::Conversation.find(conversation_id)
      @message = Community::Message.find(message_id)
      @url = "#{root_url.chomp('/')}#{"/forum/conversations/#{@conversation.id}"}"
      assign_notification_unsubscribe("forum.private_message")

      mail(to: @user.email, subject: "来自 #{@message.user.username} 的私信")
    end

    def mention(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @mention_unsubscribe_url = notification_type_unsubscribe_url_for(@user, "forum.mention")
      @notification_unsubscribe_url = @mention_unsubscribe_url

      mail(to: @user.email, subject: "#{@post.user.username} 在主题中提到了你")
    end

    def here(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"

      mail(to: @user.email, subject: "#{@post.user.username} 在主题中 @here 提及了你")
    end

    def section_topic(user_id, topic_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.section_topic")

      mail(to: @user.email, subject: "分区有新主题：#{@topic.title.truncate(60)}")
    end

    def tag_topic(user_id, topic_id, tag_names)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @tag_names = tag_names
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.tag_topic")

      mail(to: @user.email, subject: "关注标签有新主题：#{@topic.title.truncate(60)}")
    end

    def followed_topic(user_id, topic_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @author = @topic.user
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
      assign_notification_unsubscribe("forum.followed_topic")

      mail(to: @user.email, subject: "#{@author.username} 发布了新主题")
    end

    def followed_reply(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.followed_reply")

      mail(to: @user.email, subject: "#{@post.user.username} 回复了主题：#{@topic.title.truncate(60)}")
    end

    def digest(user_id, notification_ids)
      @user = User.find(user_id)
      @notifications = Notification.where(id: notification_ids, user: @user).order(created_at: :desc)
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
      @topics = Community::Topic.where(id: topic_ids).order(created_at: :desc)
      @filter_labels = Community::SavedSearchFilterSummary.call(@search)
      @url = "#{root_url.chomp('/')}#{forum_search_path(search_url_for(@search))}"
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @unsubscribe_url = "#{root_url.chomp('/')}#{unsubscribe_forum_saved_searches_path(token: Community::SavedSearchUnsubscribeToken.generate(@search))}"
      @rss_url = "#{root_url.chomp('/')}#{Community::SavedSearchPresenter.rss_path(@search)}"

      mail(to: @user.email, subject: "保存的搜索有新结果：#{@search.name}")
    end

    def post_edited(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @editor = @post.user
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"

      mail(to: @user.email, subject: "帖子已编辑：#{@topic.title.truncate(60)}")
    end

    def bookmark_reminder(user_id, bookmark_id)
      @user = User.find(user_id)
      @bookmark = Community::Bookmark.find(bookmark_id)
      @topic = @bookmark.topic
      return unless @topic

      @url = if @bookmark.forum_post_id.present? && @bookmark.post
               "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@bookmark.post.id}"}"
      else
               "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
      end
      @note = @bookmark.note
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"

      mail(to: @user.email, subject: "书签提醒：#{@topic.title.truncate(60)}")
    end

    def user_warning(user_id, warning_id)
      @user = User.find(user_id)
      @warning = Community::UserWarning.find(warning_id)
      @url = "#{root_url.chomp('/')}#{"/forum/users/#{@user.username}"}"
      mail(to: @user.email, subject: "社区警告通知")
    end

    def badge_earned(user_id, badge_id)
      @user = User.find(user_id)
      @badge = Community::Badge.find(badge_id)
      @url = "#{root_url.chomp('/')}#{forum_badge_path(@badge.slug)}"
      mail(to: @user.email, subject: "你获得了徽章：#{@badge.name}")
    end

    def topic_assigned(user_id, topic_id, actor_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @actor = User.find(actor_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
      mail(to: @user.email, subject: "主题已指派给你：#{@topic.title.truncate(60)}")
    end

    def trust_level_up(user_id, level, level_name)
      @user = User.find(user_id)
      @level = level
      @level_name = level_name
      @url = "#{root_url.chomp('/')}#{forum_user_path(@user.username)}"
      mail(to: @user.email, subject: "信任等级提升：#{@level_name}")
    end

    def post_reaction(user_id, post_id, reactor_id, emoji)
      @user = User.find(user_id)
      @post = Community::Post.find(post_id)
      @reactor = User.find(reactor_id)
      @emoji = emoji
      @topic = @post.topic
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      assign_notification_unsubscribe("forum.reaction")
      mail(to: @user.email, subject: "#{@reactor.username} 对你的帖子做出了反应 #{@emoji}")
    end

    def post_quoted(user_id, post_id, quoter_id, quoted_post_id)
      @user = User.find(user_id)
      @post = Community::Post.find(post_id)
      @quoter = User.find(quoter_id)
      @quoted_post = Community::Post.find(quoted_post_id)
      @topic = @post.topic
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      mail(to: @user.email, subject: "#{@quoter.username} 引用了你的帖子")
    end

    def topic_solved(user_id, topic_id, post_id, actor_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @actor = User.find(actor_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"
      mail(to: @user.email, subject: "你的主题已标记为已解决")
    end

    def topic_invite(user_id, topic_id, inviter_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @inviter = User.find(inviter_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
      mail(to: @user.email, subject: "#{@inviter.username} 邀请你关注主题")
    end

    def poll_closed(user_id, poll_id, actor_id)
      @user = User.find(user_id)
      @poll = Community::Poll.find(poll_id)
      @topic = @poll.topic
      @actor = User.find(actor_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"
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

  private

    def assign_notification_unsubscribe(notification_type)
      @preferences_url = "#{root_url.chomp('/')}#{forum_preferences_path}"
      @notification_unsubscribe_url = notification_type_unsubscribe_url_for(@user, notification_type)
    end

    def search_url_for(search)
      Community::SavedSearchPresenter.url_params(search)
    end
  end
end
