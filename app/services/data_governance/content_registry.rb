# frozen_string_literal: true

module DataGovernance
  class ContentRegistry
    Entry = Data.define(:type, :model_name, :label_attribute)

    ENTRIES = [
      Entry.new(type: "Community::Topic", model_name: "Community::Topic", label_attribute: :title),
      Entry.new(type: "Community::Post", model_name: "Community::Post", label_attribute: :body),
      Entry.new(type: "Community::Message", model_name: "Community::Message", label_attribute: :body),
      Entry.new(type: "Community::PostAttachment", model_name: "Community::PostAttachment", label_attribute: :filename),
      Entry.new(type: "Community::ProfilePost", model_name: "Community::ProfilePost", label_attribute: :body),
      Entry.new(type: "Community::ProfilePostComment", model_name: "Community::ProfilePostComment", label_attribute: :body)
    ].freeze
    INDEX = ENTRIES.index_by(&:type).freeze

    class << self
      def entries
        ENTRIES
      end

      def supported?(target_or_type)
        INDEX.key?(normalize_type(target_or_type))
      end

      def resolve(target_type:, target_id:)
        entry = INDEX[target_type.to_s]
        return unless entry

        lifecycle_scope(entry.model_name.constantize).find_by(id: target_id)
      end

      def resolve_reference(target_type:, reference:)
        entry = INDEX[target_type.to_s]
        return unless entry

        model = entry.model_name.constantize
        scope = lifecycle_scope(model)
        normalized = reference.to_s.strip
        return if normalized.blank?

        if model.column_names.include?("public_id")
          by_public_id = scope.find_by(public_id: normalized)
          return by_public_id if by_public_id
        end

        scope.find_by(id: Integer(normalized, exception: false))
      end

      def lock_record!(target)
        primary_key = target.class.primary_key
        locked = target.class.unscoped
          .where(primary_key => target.id)
          .lock
          .first
        locked || raise(ActiveRecord::RecordNotFound)
      end

      def snapshot(target)
        entry = INDEX.fetch(target.class.base_class.name)
        owner = content_owner(target)
        raw_label = target.public_send(entry.label_attribute).to_s.squish

        {
          type: entry.type,
          label: raw_label.truncate(160),
          public_id: target.respond_to?(:public_id) ? target.public_id : nil,
          owner: owner && {
            id: owner.id,
            public_id: owner.respond_to?(:public_id) ? owner.public_id : nil,
            username: owner.respond_to?(:username) ? owner.username : nil
          }
        }
      end

      def purged_snapshot(target)
        owner = content_owner(target)

        {
          type: target.class.base_class.name,
          public_id: target.respond_to?(:public_id) ? target.public_id : nil,
          owner: owner && {
            id: owner.id,
            public_id: owner.respond_to?(:public_id) ? owner.public_id : nil
          }
        }
      end

      def scrubbed_snapshot(snapshot, type:)
        raw = snapshot.to_h.stringify_keys
        owner = raw.fetch("owner", {}).to_h.stringify_keys.slice("id", "public_id").compact

        {
          type:,
          public_id: raw["public_id"],
          owner: owner.presence
        }.compact
      end

      def evidence_targets(target)
        targets = [ target ]

        case target
        when Community::Topic
          posts = Community::Post.with_discarded.where(forum_topic_id: target.id).to_a
          targets.concat(posts)
          if defined?(Community::PostAttachment)
            targets.concat(
              Community::PostAttachment.with_discarded.where(forum_post_id: posts.map(&:id)).to_a
            )
          end
        when Community::Post
          targets.concat(Community::PostAttachment.with_discarded.where(forum_post_id: target.id).to_a)
        when Community::Message
          targets.concat(Community::PostAttachment.with_discarded.where(forum_message_id: target.id).to_a)
        when Community::PostAttachment
          targets << parent_post(target)
          targets << parent_message(target)
        when Community::ProfilePost
          targets.concat(
            Community::ProfilePostComment.with_discarded.where(profile_post_id: target.id).to_a
          )
        end

        targets.compact.uniq { |item| [ item.class.base_class.name, item.id ] }
      end

      def hold_targets(target)
        targets = evidence_targets(target)
        targets.concat(targets.filter_map { |item| content_owner(item) })
        targets << parent_topic(target)
        targets << target.conversation if target.respond_to?(:conversation) && target.conversation
        if target.is_a?(Community::ProfilePostComment)
          targets << Community::ProfilePost.with_discarded.find_by(id: target.profile_post_id)
        elsif target.respond_to?(:profile_post) && target.profile_post
          targets << target.profile_post
        end
        targets.compact.uniq { |item| [ item.class.base_class.name, item.id ] }
      end

      def content_owner(target)
        return target.user if target.respond_to?(:user)
        return target.author if target.respond_to?(:author)

        nil
      end

      def before_permanent_purge(target, at: Time.current)
        cleanup_upload_ids = []
        case target
        when Community::Topic
          post_ids = Community::Post.with_discarded.where(forum_topic_id: target.id).pluck(:id)
          Community::Topic.unscoped.where(redirect_to_topic_id: target.id).update_all(redirect_to_topic_id: nil)
          Community::Topic.unscoped.where(solved_post_id: post_ids).update_all(solved_post_id: nil) if post_ids.any?
          Community::Topic.unscoped.where(source_post_id: post_ids).update_all(source_post_id: nil) if post_ids.any?
        when Community::Post
          Community::Topic.unscoped.where(solved_post_id: target.id).update_all(solved_post_id: nil)
          Community::Topic.unscoped.where(source_post_id: target.id).update_all(source_post_id: nil)
        when Community::Message
          attachment_ids = Community::PostAttachment.with_discarded
            .where(forum_message_id: target.id)
            .pluck(:id)
          cleanup_upload_ids = Community::Upload
            .where(forum_post_attachment_id: attachment_ids)
            .where.not(status: "cleaned")
            .pluck(:id)
          Community::Upload.where(id: cleanup_upload_ids).find_each do |upload|
            upload.schedule_cleanup!(at: at)
          end
        end

        cleanup_upload_ids
      end

      def enqueue_scheduled_upload_cleanup(upload_ids)
        Array(upload_ids).uniq.each do |upload_id|
          Maintenance::CleanupForumUploadsJob.perform_later(upload_id: upload_id)
        end
      rescue StandardError => error
        Rails.logger.error(
          "[DataGovernance::ContentRegistry] upload cleanup enqueue failed " \
          "upload_ids=#{Array(upload_ids).join(',')} error=#{error.class}"
        )
      end

      def after_lifecycle_change(target)
        topic = parent_topic(target)
        Community::Post.sync_topic_counters!(topic) if topic&.persisted?
      end

      private

      def normalize_type(target_or_type)
        return target_or_type.class.base_class.name unless target_or_type.is_a?(String)

        target_or_type
      end

      def lifecycle_scope(model)
        model.respond_to?(:with_discarded) ? model.with_discarded : model.all
      end

      def parent_post(target)
        return unless target.respond_to?(:forum_post_id)

        Community::Post.with_discarded.find_by(id: target.forum_post_id)
      end

      def parent_message(target)
        return unless target.respond_to?(:forum_message_id)

        Community::Message.with_discarded.find_by(id: target.forum_message_id)
      end

      def parent_topic(target)
        case target
        when Community::Post
          Community::Topic.with_discarded.find_by(id: target.forum_topic_id)
        when Community::PostAttachment
          post = parent_post(target)
          Community::Topic.with_discarded.find_by(id: post&.forum_topic_id)
        end
      end
    end
  end
end
