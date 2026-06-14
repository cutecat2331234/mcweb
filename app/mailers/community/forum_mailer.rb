# frozen_string_literal: true

module Community
  class ForumMailer < ApplicationMailer
    def topic_reply(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"

      mail(to: @user.email, subject: "主题有新回复：#{@topic.title.truncate(60)}")
    end

    def private_message(user_id, conversation_id, message_id)
      @user = User.find(user_id)
      @conversation = Community::Conversation.find(conversation_id)
      @message = Community::Message.find(message_id)
      @url = "#{root_url.chomp('/')}#{"/forum/conversations/#{@conversation.id}"}"

      mail(to: @user.email, subject: "来自 #{@message.user.username} 的私信")
    end

    def mention(user_id, topic_id, post_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @post = Community::Post.find(post_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}#post-#{@post.id}"}"

      mail(to: @user.email, subject: "#{@post.user.username} 在主题中提到了你")
    end

    def section_topic(user_id, topic_id)
      @user = User.find(user_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      @url = "#{root_url.chomp('/')}#{"/forum/topics/#{@topic.public_id}"}"

      mail(to: @user.email, subject: "分区有新主题：#{@topic.title.truncate(60)}")
    end

    def digest(user_id, notification_ids)
      @user = User.find(user_id)
      @notifications = Notification.where(id: notification_ids, user: @user).order(created_at: :desc)

      mail(to: @user.email, subject: "论坛摘要 — #{@notifications.count} 条新动态")
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

      mail(to: @user.email, subject: "书签提醒：#{@topic.title.truncate(60)}")
    end

    def user_warning(user_id, warning_id)
      @user = User.find(user_id)
      @warning = Community::UserWarning.find(warning_id)
      @url = "#{root_url.chomp('/')}#{"/forum/users/#{@user.username}"}"
      mail(to: @user.email, subject: "社区警告通知")
    end
  end
end
