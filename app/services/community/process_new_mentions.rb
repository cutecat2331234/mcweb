# frozen_string_literal: true

module Community
  class ProcessNewMentions < ApplicationService
    def initialize(old_body:, new_body:, author:, post:, topic:)
      @old_body = old_body.to_s
      @new_body = new_body.to_s
      @author = author
      @post = post
      @topic = topic
    end

    def call
      old_names = @old_body.scan(ProcessMentions::MENTION_PATTERN).flatten.uniq
      new_names = @new_body.scan(ProcessMentions::MENTION_PATTERN).flatten.uniq
      added = new_names - old_names
      return ServiceResult.success(mentioned: []) if added.empty?

      synthetic = added.map { |name| "@#{name}" }.join(" ")
      Community::ProcessMentions.call(body: synthetic, author: @author, post: @post, topic: @topic)
    end
  end
end
