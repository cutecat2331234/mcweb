# frozen_string_literal: true

module Community
  class EditTopic < ApplicationService
    NOT_PROVIDED = Object.new.freeze

    def initialize(user:, topic:, title: nil, tag_names: nil, prefix: nil, poll_params: nil, custom_fields: NOT_PROVIDED)
      @user = user
      @topic = topic
      @title = title&.strip
      @tag_names = tag_names
      @prefix = prefix
      @poll_params = poll_params
      @custom_fields = custom_fields
      apply_plugin_filters!
    end

    def call
      return call_core unless plugin_service_decorators_available?

      Mcweb::Plugins.call_service(
        "forum.topic.edit",
        input: plugin_attributes,
        context: { user: @user, topic: @topic }
      ) do |input, _context|
        apply_plugin_attributes!(input)
        call_core
      end
    end

    def call_core
      unless Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      return ServiceResult.failure(error: :this_topic_is_archived) if @topic.archived_at.present?
      return ServiceResult.failure(error: :you_cannot_edit_this_topic) unless can_edit?

      tag_result = nil
      poll_result = nil
      field_result = nil
      state_result = nil
      actor_id = @user.id
      topic_owner_id = @topic.user_id
      Community::Topic.transaction do
        locked_users = nil
        Identity::UserMutationLock.with_users(
          users: [ actor_id, topic_owner_id ]
        ) { |users| locked_users = users }
        @user = locked_users.fetch(actor_id)
        topic_owner = locked_users.fetch(topic_owner_id)
        if @user.deleted? || @user.banned?
          state_result = ServiceResult.failure(
            error: @user.deleted? ? :account_deleted : :account_banned
          )
          raise ActiveRecord::Rollback
        end

        @topic = Community::Topic.with_discarded.lock.find_by(id: @topic.id)
        unless @topic && @topic.user_id == topic_owner.id && !topic_owner.deleted? &&
            @topic.archived_at.nil? && can_edit?
          state_result = ServiceResult.failure(error: :topic_not_available)
          raise ActiveRecord::Rollback
        end

        attrs = {}
        attrs[:title] = @title if @title.present?
        attrs[:prefix] = valid_prefix if @prefix != nil
        @topic.update!(attrs) if attrs.any?
        if @tag_names
          tag_result = Community::SyncTopicTags.call(topic: @topic, tag_names: @tag_names, user: @user)
          raise ActiveRecord::Rollback unless tag_result.success?
        end
        if @poll_params
          poll_result = Community::EditTopicPoll.call(
            user: @user,
            topic: @topic,
            **@poll_params
          )
          raise ActiveRecord::Rollback unless poll_result.success?
        end
        unless @custom_fields.equal?(NOT_PROVIDED)
          field_result = Community::SyncTopicFieldValues.call(
            topic: @topic,
            user: @user,
            values: @custom_fields,
            require_required: true
          )
          raise ActiveRecord::Rollback unless field_result.success?
        end
      end

      return state_result if state_result&.failure?
      return tag_result if tag_result&.failure?
      return poll_result if poll_result&.failure?
      return field_result if field_result&.failure?

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def plugin_service_decorators_available?
      defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:call_service)
    end

    def plugin_attributes
      {
        title: @title,
        title_provided: !@title.nil?,
        tag_names: @tag_names,
        tag_names_provided: !@tag_names.nil?,
        prefix: @prefix,
        prefix_provided: !@prefix.nil?,
        poll_params: @poll_params,
        poll_params_provided: !@poll_params.nil?,
        custom_fields: @custom_fields.equal?(NOT_PROVIDED) ? nil : @custom_fields,
        custom_fields_provided: !@custom_fields.equal?(NOT_PROVIDED)
      }
    end

    def can_edit?
      Community::SectionModeration.can_edit_topic?(user: @user, topic: @topic)
    end

    def valid_prefix
      return nil if @prefix.blank?

      allowed = @topic.section.prefix_names
      allowed.include?(@prefix) ? @prefix : nil
    end

    def apply_plugin_filters!
      return unless defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:apply_filter)

      filtered = Mcweb::Plugins.apply_filter(
        "forum.topic.edit.attributes",
        plugin_attributes,
        context: { user: @user, topic: @topic }
      )
      apply_plugin_attributes!(filtered)
    rescue StandardError => e
      Rails.logger.error("[mcweb.plugins] forum.topic.edit.attributes host integration failed: #{e.class}: #{e.message}")
    end

    def apply_plugin_attributes!(filtered)
      return unless filtered.is_a?(Hash)

      boolean = ActiveModel::Type::Boolean.new
      title = boolean.cast(filtered["title_provided"]) ? filtered["title"].to_s.strip : nil
      tag_names = boolean.cast(filtered["tag_names_provided"]) ? filtered["tag_names"] : nil
      prefix = boolean.cast(filtered["prefix_provided"]) ? filtered["prefix"] : nil
      poll_params =
        if boolean.cast(filtered["poll_params_provided"])
          value = filtered["poll_params"]
          raise ArgumentError, "poll_params filter value must be a mapping" unless value.respond_to?(:to_h)

          value.to_h.symbolize_keys
        end
      custom_fields =
        if boolean.cast(filtered["custom_fields_provided"])
          filtered["custom_fields"]
        else
          NOT_PROVIDED
        end

      @title = title
      @tag_names = tag_names
      @prefix = prefix
      @poll_params = poll_params
      @custom_fields = custom_fields
    end
  end
end
