# frozen_string_literal: true

module Community
  class CreateTopicFromPost < ApplicationService
    def initialize(user:, post:, title: nil, body: nil, section: nil, ip_address: nil)
      @user = user
      @post = post
      @source_topic = post.topic
      @title = title.to_s.strip.presence
      @body = body.to_s.strip
      @requested_section = section
      @section = section || @source_topic.section
      @ip_address = ip_address
    end

    def call
      access_result = create_access_result
      return access_result if access_result.failure?

      topic_title = @title || I18n.t("mcweb.forum.create_topic_from_post.default_title", title: @source_topic.title).truncate(120)
      opening_body = build_opening_body

      topic = nil
      state_result = nil
      lock_attempts = 0
      begin
        Community::Topic.transaction do
          @user = User.lock.find(@user.id)
          state_result = account_write_access_result
          raise ActiveRecord::Rollback if state_result.failure?

          target_section = @requested_section || @source_topic.section
          @source_topic, _source_section, @section = Community::SectionHierarchyLock.lock_topic!(
            @source_topic,
            target_section
          )
          @post.reload
          @post.association(:topic).target = @source_topic
          state_result = create_access_result
          raise ActiveRecord::Rollback if state_result.failure?

          topic = Community::Topic.create!(
            public_id: generate_public_id,
            section: @section,
            user: @user,
            title: topic_title,
            status: "published",
            source_post: @post,
            last_posted_at: Time.current,
            last_post_user: @user,
            replies_count: 0
          )

          Community::Post.create!(
            topic: topic,
            user: @user,
            floor_number: 1,
            body: opening_body,
            quoted_post: @post,
            status: "published"
          )

          Community::Subscription.subscribe!(@user, topic)
          Community::ReadState.mark_read!(@user, topic, floor: 1)
        end
      rescue Community::SectionHierarchyLock::TopicSectionChanged,
        Community::SectionHierarchyLock::HierarchyChanged,
        ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_topic = Community::Topic.with_discarded.find_by(id: @source_topic.id)
        fresh_section = @requested_section && Community::Section.find_by(id: @requested_section.id)
        if lock_attempts <= 2 && fresh_topic && (!@requested_section || fresh_section)
          @source_topic = fresh_topic
          @section = fresh_section || fresh_topic.section
          retry
        end
        state_result = ServiceResult.failure(error: :section_not_available)
      rescue ActiveRecord::RecordNotFound
        state_result = ServiceResult.failure(error: :post_not_available)
      end

      return state_result if state_result&.failure?

      opening_post = topic.posts.first
      Administration::AuditLogger.call(
        actor: @user,
        action: "community.topic_forked_from_post",
        resource: topic,
        ip_address: @ip_address
      )

      Community::ProcessMentions.call(body: opening_body, author: @user, post: opening_post, topic: topic) if opening_post
      Community::NotifySectionTopic.call(topic: topic)
      Community::NotifyPostQuoted.call(post: opening_post, quoter: @user, quoted_post: @post) if opening_post
      ServiceResult.success(topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def account_write_access_result
      return ServiceResult.failure(error: :account_deleted) if @user.deleted?
      return ServiceResult.failure(error: :account_banned) if @user.banned?

      ServiceResult.success
    end

    def create_access_result
      return ServiceResult.failure(error: :post_not_available) unless PostAccess.readable?(post: @post, user: @user)

      unless Community::SectionAccess.view?(section: @section, user: @user)
        return ServiceResult.failure(error: :section_not_available)
      end

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: :cannot_create_topic_in_section)
      end

      unless @section.trust_allowed?(@user, :create_topic)
        return ServiceResult.failure(error: :trust_level_too_low)
      end

      unless @section.writable_by?(@user, :create_topic)
        return ServiceResult.failure(error: :section_read_only)
      end

      ServiceResult.success
    end

    def build_opening_body
      source_url = Rails.application.routes.url_helpers.forum_topic_path(@source_topic, anchor: "post-#{@post.id}")
      header = I18n.t(
        "mcweb.forum.create_topic_from_post.quote_header",
        floor: @post.floor_number,
        author: @post.user.username,
        url: source_url
      )
      quote = @post.body.lines.map { |line| "> #{line.chomp}" }.join("\n")
      parts = [ header, "", quote ]
      parts << "" << @body if @body.present?
      parts.join("\n")
    end

    def generate_public_id
      "topic_#{SecureRandom.alphanumeric(16)}"
    end
  end
end
