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
  end
end
