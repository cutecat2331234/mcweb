# frozen_string_literal: true

require_relative "result"
require_relative "snapshot"

module Mcweb
  module PluginApi
    module V1
      # User-bound forum reads and writes. Every lookup composes the canonical
      # section scope with ForumAccess' record predicate. Writes delegate to the
      # existing application services so moderation, spam and trust rules remain
      # owned by core.
      class Forum
        DEFAULT_LIMIT = 50
        MAX_LIMIT = 100
        MAX_SEARCH_LENGTH = 500
        MAX_FILTER_LENGTH = 255
        SEARCH_SORTS = %w[recent oldest relevance].freeze
        TOPIC_MODERATION_ACTIONS = %w[
          lock unlock pin unpin bump hide unhide feature unfeature
          enable_wiki disable_wiki global_announcement
          remove_global_announcement unlist list archive unarchive
          assign unassign
        ].freeze
        POST_MODERATION_ACTIONS = %w[
          hide unhide enable_wiki disable_wiki set_staff_notice
          clear_staff_notice change_author
        ].freeze
        NOT_PROVIDED = Object.new.freeze

        def initialize(capability_auditor: nil)
          @capability_auditor = capability_auditor
          freeze
        end

        def find_category(user:, id: nil, slug: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          category, failure = resolve_category(user:, id:, slug:)
          failure || Result.success(Snapshot.category(category))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def category_scope(user:, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          snapshots = visible_category_scope(user)
            .order(:position, :id)
            .limit(limit)
            .map { |category| Snapshot.category(category) }
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :categories, :category_scope

        def find_section(user:, id: nil, slug: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          section, failure = resolve_section(user:, id:, slug:)
          failure || Result.success(Snapshot.section(section))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def section_scope(user:, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          relation = Community::SectionAccess.scope(
            relation: Community::Section.all,
            user:
          )
          snapshots = relation.order(:position, :id).limit(limit).map do |section|
            Snapshot.section(section)
          end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :sections, :section_scope

        def find_tag(user:, id: nil, slug: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          tag, failure = resolve_tag(user:, id:, slug:)
          failure || Result.success(Snapshot.tag(tag))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def tag_scope(user:, query: nil, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          query, failure = resolve_optional_filter(query, name: "query")
          return failure if failure

          relation = Community::Tag.usable_by(user).where(canonical_tag_id: nil)
          if query
            needle = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
            relation = relation.where("name ILIKE ? OR slug ILIKE ?", needle, needle)
          end
          snapshots = relation.order(:name, :id).limit(limit).map { |tag| Snapshot.tag(tag) }
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :tags, :tag_scope

        def find_topic(user:, id: nil, public_id: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          topic, failure = resolve_topic(user:, id:, public_id:)
          failure || Result.success(Snapshot.topic(topic))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def topic_scope(user:, section_id: nil, section_slug: nil, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          relation = Community::Topic.all
          unless section_id.nil? && section_slug.nil?
            section, failure = resolve_section(user:, id: section_id, slug: section_slug)
            return failure if failure

            relation = relation.where(forum_section_id: section.id)
          end
          relation = Community::ForumAccess.topic_scope(relation:, user:)
          Result.success(visible_snapshots(relation, limit:) do |topic|
            Snapshot.topic(topic) if Community::ForumAccess.topic_visible?(topic:, user:)
          end)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :topics, :topic_scope

        def find_post(user:, id:)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          post, failure = resolve_post(user:, id:)
          failure || Result.success(Snapshot.post(post))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def post_scope(user:, topic_id: nil, topic_public_id: nil, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          relation = Community::ForumAccess.post_scope(
            relation: Community::Post.where(forum_topic_id: topic.id),
            user:
          )
          Result.success(visible_snapshots(relation, limit:) do |post|
            Snapshot.post(post) if Community::ForumAccess.post_visible?(post:, user:)
          end)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :posts, :post_scope

        def search_topics(
          user:, query:, section_slug: nil, category_slug: nil,
          tag_slug: nil, author: nil, sort: "recent", limit: DEFAULT_LIMIT
        )
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          query, failure = resolve_search_query(query)
          return failure if failure

          sort, failure = resolve_search_sort(sort)
          return failure if failure

          filters, failure = resolve_search_filters(
            section: section_slug,
            category: category_slug,
            tag: tag_slug,
            author:
          )
          return failure if failure

          service_result = Community::BuildAdHocSearchTopicScope.call(
            params: filters.merge(q: query, topic_sort: sort),
            user:
          )
          return Result.from_service_result(service_result) if service_result.failure?

          relation = service_result.value.fetch(:scope)
          snapshots = relation.limit(limit).filter_map do |topic|
            Snapshot.topic(topic) if Community::ForumAccess.listed_topic_visible?(topic:, user:)
          end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def search_posts(
          user:, query:, section_slug: nil, category_slug: nil,
          tag_slug: nil, author: nil, sort: "recent", limit: DEFAULT_LIMIT
        )
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          query, failure = resolve_search_query(query)
          return failure if failure

          sort, failure = resolve_search_sort(sort)
          return failure if failure

          filters, failure = resolve_search_filters(
            section: section_slug,
            category: category_slug,
            tag: tag_slug,
            author:
          )
          return failure if failure

          relation = Community::ForumAccess.listed_post_scope(
            relation: Community::Post.all,
            user:
          )
          relation, failure = apply_post_search_filters(relation, filters:, user:)
          return failure if failure

          relation = relation.where(
            "to_tsvector('simple', coalesce(forum_posts.body, '')) @@ plainto_tsquery('simple', ?)",
            query
          )
          relation = order_post_search(relation, query:, sort:)
          snapshots = relation.limit(limit).filter_map do |post|
            Snapshot.post(post) if Community::ForumAccess.listed_post_visible?(post:, user:)
          end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def create_topic(
          user:, title:, body:, section_id: nil, section_slug: nil,
          tag_names: nil, prefix: nil, attachment_ids: nil,
          custom_fields: nil, ip_address: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          section, failure = resolve_section(user:, id: section_id, slug: section_slug)
          return failure if failure

          service_result = Community::CreateTopic.call(
            user:,
            section:,
            title:,
            body:,
            tag_names:,
            prefix:,
            attachment_ids:,
            custom_fields:,
            ip_address:
          )
          Result.from_service_result(service_result) { |topic| Snapshot.topic(topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def create_post(
          user:, body:, topic_id: nil, topic_public_id: nil,
          quoted_post_id: nil, parent_post_id: nil,
          attachment_ids: nil, ip_address: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          quoted_post, failure = resolve_optional_post(user:, id: quoted_post_id)
          return failure if failure

          parent_post, failure = resolve_optional_post(user:, id: parent_post_id)
          return failure if failure

          service_result = Community::CreatePost.call(
            user:,
            topic:,
            body:,
            quoted_post:,
            parent_post:,
            attachment_ids:,
            ip_address:
          )
          Result.from_service_result(service_result) { |post| Snapshot.post(post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def edit_topic(
          user:, topic_id: nil, topic_public_id: nil,
          title: NOT_PROVIDED, tag_names: NOT_PROVIDED,
          prefix: NOT_PROVIDED, custom_fields: NOT_PROVIDED
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          attributes = {
            title:,
            tag_names:,
            prefix:,
            custom_fields:
          }.reject { |_key, value| value.equal?(NOT_PROVIDED) }
          if attributes.empty?
            return Result.failure(code: "invalid_argument", error: "provide at least one topic attribute")
          end

          if attributes.key?(:title) && !attributes[:title].to_s.strip.length.between?(1, 255)
            return Result.failure(
              code: "invalid_argument",
              error: "title must be between 1 and 255 characters"
            )
          end

          service_result = Community::EditTopic.call(user:, topic:, **attributes)
          Result.from_service_result(service_result) { |updated_topic| Snapshot.topic(updated_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def edit_post(
          user:, id:, body:, expected_revision: nil, reason: nil, attachment_ids: NOT_PROVIDED
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id:)
          return failure if failure

          arguments = { user:, post:, body:, expected_revision:, reason: }
          arguments[:attachment_ids] = attachment_ids unless attachment_ids.equal?(NOT_PROVIDED)
          service_result = Community::EditPost.call(**arguments)
          Result.from_service_result(service_result) { |updated_post| Snapshot.post(updated_post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def move_topic(
          user:, topic_id: nil, topic_public_id: nil,
          section_id: nil, section_slug: nil, leave_redirect: false
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          leave_redirect, failure = resolve_boolean(leave_redirect, name: "leave_redirect")
          return failure if failure

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          section, failure = resolve_section(user:, id: section_id, slug: section_slug)
          return failure if failure

          service_result = Community::MoveTopic.call(
            user:,
            topic:,
            section:,
            leave_redirect:
          )
          Result.from_service_result(service_result) { |moved_topic| Snapshot.topic(moved_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def copy_topic(
          user:, topic_id: nil, topic_public_id: nil,
          section_id: nil, section_slug: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          section, failure = resolve_section(user:, id: section_id, slug: section_slug)
          return failure if failure

          service_result = Community::CopyTopic.call(user:, topic:, section:)
          Result.from_service_result(service_result) { |copied_topic| Snapshot.topic(copied_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def merge_topics(
          user:,
          source_topic_id: nil, source_topic_public_id: nil,
          target_topic_id: nil, target_topic_public_id: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          source, failure = resolve_topic(
            user:,
            id: source_topic_id,
            public_id: source_topic_public_id
          )
          return failure if failure

          target, failure = resolve_topic(
            user:,
            id: target_topic_id,
            public_id: target_topic_public_id
          )
          return failure if failure

          service_result = Community::MergeTopics.call(
            user:,
            source:,
            target_public_id: target.public_id
          )
          Result.from_service_result(service_result) { |merged_topic| Snapshot.topic(merged_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def split_topic(
          user:, post_id:, topic_id: nil, topic_public_id: nil,
          title: nil, section_id: nil, section_slug: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          section = nil
          unless section_id.nil? && section_slug.nil?
            section, failure = resolve_section(user:, id: section_id, slug: section_slug)
            return failure if failure
          end

          service_result = Community::SplitTopic.call(
            user:,
            topic:,
            post:,
            title:,
            section:
          )
          Result.from_service_result(service_result) { |split_topic| Snapshot.topic(split_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def delete_post(user:, id:)
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id:)
          return failure if failure

          service_result = Community::DeletePost.call(actor: user, post:)
          Result.from_service_result(service_result) { |deleted_post| Snapshot.post(deleted_post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def restore_post(user:, id:)
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_deleted_post_for_moderation(user:, id:)
          return failure if failure

          service_result = Community::RestorePost.call(actor: user, post:)
          Result.from_service_result(service_result) { |restored_post| Snapshot.post(restored_post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def approve_post(user:, id:)
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id:)
          return failure if failure

          service_result = Community::ApprovePost.call(actor: user, post:)
          Result.from_service_result(service_result) { |approved_post| Snapshot.post(approved_post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def reject_post(user:, id:, reason: nil)
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id:)
          return failure if failure

          service_result = Community::RejectPost.call(actor: user, post:, reason:)
          Result.from_service_result(service_result) { |rejected_post| Snapshot.post(rejected_post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def moderate_topic(
          user:, action:, topic_id: nil, topic_public_id: nil,
          lock_reason: nil, assignee_username: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          action, failure = resolve_action(
            action,
            allowed: TOPIC_MODERATION_ACTIONS,
            resource: "topic"
          )
          return failure if failure

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          service_result = Community::ModerateTopic.call(
            user:,
            topic:,
            action:,
            lock_reason:,
            assignee_username:
          )
          Result.from_service_result(service_result) { |moderated_topic| Snapshot.topic(moderated_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def moderate_post(
          user:, id:, action:, staff_notice: nil, new_username: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          action, failure = resolve_action(
            action,
            allowed: POST_MODERATION_ACTIONS,
            resource: "post"
          )
          return failure if failure

          post, failure = resolve_post(user:, id:)
          return failure if failure

          service_result = Community::ModeratePost.call(
            user:,
            post:,
            action:,
            staff_notice:,
            new_username:
          )
          Result.from_service_result(service_result) { |moderated_post| Snapshot.post(moderated_post) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def mark_topic_solved(
          user:, post_id:, topic_id: nil, topic_public_id: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          service_result = Community::MarkTopicSolved.call(user:, topic:, post:)
          Result.from_service_result(service_result) { |solved_topic| Snapshot.topic(solved_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def unsolve_topic(user:, topic_id: nil, topic_public_id: nil)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          service_result = Community::UnsolveTopic.call(user:, topic:)
          Result.from_service_result(service_result) { |unsolved_topic| Snapshot.topic(unsolved_topic) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def create_topic_staff_note(
          user:, body:, topic_id: nil, topic_public_id: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          service_result = Community::CreateTopicStaffNote.call(
            actor: user,
            topic:,
            body:
          )
          Result.from_service_result(service_result) { |note| Snapshot.topic_staff_note(note) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def invite_topic_watcher(
          user:, username:, topic_id: nil, topic_public_id: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          service_result = Community::InviteTopicWatcher.call(
            inviter: user,
            topic:,
            username:
          )
          Result.from_service_result(service_result) { |invite| Snapshot.topic_invite(invite) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def ban_topic_reply(
          user:, reason: nil, expires_at: nil,
          topic_id: nil, topic_public_id: nil,
          target_user_id: nil, target_username: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          target_user, failure = resolve_user(id: target_user_id, username: target_username)
          return failure if failure

          expires_at, failure = resolve_optional_future_time(expires_at)
          return failure if failure

          service_result = Community::BanTopicReply.call(
            actor: user,
            topic:,
            user: target_user,
            reason:,
            expires_at:
          )
          Result.from_service_result(service_result) do |ban|
            Snapshot.topic_reply_ban_state(
              topic:,
              user: target_user,
              banned: true,
              ban:
            )
          end
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def unban_topic_reply(
          user:,
          topic_id: nil, topic_public_id: nil,
          target_user_id: nil, target_username: nil
        )
          audit("forum.moderate")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          target_user, failure = resolve_user(id: target_user_id, username: target_username)
          return failure if failure

          service_result = Community::UnbanTopicReply.call(
            actor: user,
            topic:,
            user: target_user
          )
          Result.from_service_result(service_result) do
            Snapshot.topic_reply_ban_state(
              topic:,
              user: target_user,
              banned: false
            )
          end
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def find_poll(user:, id:)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          poll, failure = resolve_poll(user:, id:)
          failure || Result.success(Snapshot.poll(poll, user:))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def topic_poll(user:, topic_id: nil, topic_public_id: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          poll = topic.poll
          return not_found("poll") unless poll

          Result.success(Snapshot.poll(poll, user:))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def vote_poll(user:, id:, option_index: nil, option_indices: nil)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          poll, failure = resolve_poll(user:, id:)
          return failure if failure

          service_result = Community::VotePoll.call(
            user:,
            poll:,
            option_index:,
            option_indices:
          )
          Result.from_service_result(service_result) { Snapshot.poll(poll.reload, user:) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def revoke_poll_vote(user:, id:)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          poll, failure = resolve_poll(user:, id:)
          return failure if failure

          service_result = Community::RevokePollVote.call(user:, poll:)
          Result.from_service_result(service_result) { Snapshot.poll(poll.reload, user:) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def close_poll(user:, id:)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          poll, failure = resolve_poll(user:, id:)
          return failure if failure

          service_result = Community::ClosePoll.call(user:, poll:)
          Result.from_service_result(service_result) { |closed_poll| Snapshot.poll(closed_poll, user:) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def topic_field_definitions(user:, section_id: nil, section_slug: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          section, failure = resolve_section(user:, id: section_id, slug: section_slug)
          return failure if failure

          snapshots = Community::TopicFieldDefinition.active.ordered.filter_map do |definition|
            next unless definition.applicable_to_section?(section)

            Snapshot.topic_field_definition(
              definition,
              editable: user.present? && definition.editable_by?(user)
            )
          end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def topic_custom_fields(user:, topic_id: nil, topic_public_id: nil)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          serialized = Community::SerializeTopicFields.for_topic(topic:, user:)
          Result.success(
            serialized.map do |field|
              Snapshot.topic_field(
                topic:,
                serialized: field.merge(editable: user.present? && field[:editable])
              )
            end
          )
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :topic_fields, :topic_custom_fields

        def find_attachment(user:, id:)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          attachment, failure = resolve_attachment(user:, id:)
          failure || Result.success(Snapshot.attachment(attachment))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def post_attachments(user:, post_id:, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          snapshots = post.attachments.ordered.limit(limit).filter_map do |attachment|
            next unless Community::PostAttachmentAccess.downloadable?(attachment, user:)

            Snapshot.attachment(attachment)
          end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def unlinked_attachments(user:, limit: DEFAULT_LIMIT)
          audit("forum.read")
          return invalid_user(write: true) unless valid_writer?(user)

          limit, failure = resolve_limit(limit)
          return failure if failure

          snapshots = Community::PostAttachment.unlinked
            .where(user:)
            .ordered
            .limit(limit)
            .filter_map do |attachment|
              next unless Community::PostAttachmentAccess.downloadable?(attachment, user:)

              Snapshot.attachment(attachment)
            end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def create_attachment(user:, file:)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          service_result = Community::CreatePostAttachment.call(user:, file:)
          Result.from_service_result(service_result) { |attachment| Snapshot.attachment(attachment) }
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def sync_post_attachments(user:, post_id:, attachment_ids:)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          service_result = Community::SyncPostAttachments.call(
            user:,
            post:,
            attachment_ids:
          )
          Result.from_service_result(service_result) do |state|
            attachments = post.attachments.reload.ordered.filter_map do |attachment|
              next unless Community::PostAttachmentAccess.downloadable?(attachment, user:)

              Snapshot.attachment(attachment)
            end
            Snapshot.attachment_sync(post:, service_state: state, attachments:)
          end
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def reaction_types(user:)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          snapshots =
            if Community::ReactionType.configured?
              Community::ReactionType.active.ordered.limit(Community::ReactionType::MAX_EMOJI).map do |reaction|
                Snapshot.reaction_type(
                  emoji: reaction.emoji,
                  name: reaction.name,
                  score: reaction.score,
                  position: reaction.position
                )
              end
            else
              Community::ToggleReaction.allowed_emoji.each_with_index.map do |emoji, position|
                Snapshot.reaction_type(
                  emoji:,
                  name: emoji,
                  score: Community::Reaction.score_for(emoji),
                  position:
                )
              end
            end
          Result.success(snapshots)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def post_reactions(user:, id:)
          audit("forum.read")
          return invalid_user unless valid_reader?(user)

          post, failure = resolve_post(user:, id:)
          return failure if failure

          Result.success(
            Snapshot.reaction_summary(
              post:,
              user:,
              counts: post.reactions.group(:emoji).count,
              viewer_emojis: user ? post.reactions.where(user:).order(:id).pluck(:emoji) : []
            )
          )
        rescue StandardError => e
          Result.failure_from_exception(e)
        end
        alias_method :reaction_summary, :post_reactions

        def toggle_reaction(user:, post_id:, emoji:)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          service_result = Community::ToggleReaction.call(user:, post:, emoji:)
          Result.from_service_result(service_result) do |state|
            Snapshot.reaction_state(
              post:,
              user:,
              emoji: emoji.to_s,
              added: state.fetch(:added),
              counts: state.fetch(:counts)
            )
          end
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def topic_bookmark(user:, topic_id: nil, topic_public_id: nil)
          audit("forum.read")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          bookmarked = Community::Bookmark.exists?(user:, topic:, post: nil)
          Result.success(Snapshot.bookmark_state(resource: topic, user:, bookmarked:))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def post_bookmark(user:, post_id:)
          audit("forum.read")
          return invalid_user(write: true) unless valid_writer?(user)

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          bookmarked = Community::Bookmark.exists?(user:, post:)
          Result.success(Snapshot.bookmark_state(resource: post, user:, bookmarked:))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def set_topic_bookmark(
          user:, bookmarked:, topic_id: nil, topic_public_id: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          desired, failure = resolve_boolean(bookmarked, name: "bookmarked")
          return failure if failure

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          service_result = serialize_user_mutation(user) do
            current = Community::Bookmark.exists?(user:, topic:, post: nil)
            if current == desired
              ServiceResult.success(bookmarked: current)
            else
              Community::ToggleBookmark.call(user:, topic:)
            end
          end
          Result.from_service_result(service_result) do |state|
            Snapshot.bookmark_state(
              resource: topic,
              user:,
              bookmarked: state.fetch(:bookmarked)
            )
          end
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def bookmark_topic(**arguments)
          set_topic_bookmark(**arguments, bookmarked: true)
        end

        def unbookmark_topic(**arguments)
          set_topic_bookmark(**arguments, bookmarked: false)
        end

        def set_post_bookmark(user:, post_id:, bookmarked:)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          desired, failure = resolve_boolean(bookmarked, name: "bookmarked")
          return failure if failure

          post, failure = resolve_post(user:, id: post_id)
          return failure if failure

          service_result = serialize_user_mutation(user) do
            current = Community::Bookmark.exists?(user:, post:)
            if current == desired
              ServiceResult.success(bookmarked: current)
            else
              Community::TogglePostBookmark.call(user:, post:)
            end
          end
          Result.from_service_result(service_result) do |state|
            Snapshot.bookmark_state(
              resource: post,
              user:,
              bookmarked: state.fetch(:bookmarked)
            )
          end
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def bookmark_post(**arguments)
          set_post_bookmark(**arguments, bookmarked: true)
        end

        def unbookmark_post(**arguments)
          set_post_bookmark(**arguments, bookmarked: false)
        end

        def topic_subscription(user:, topic_id: nil, topic_public_id: nil)
          audit("forum.read")
          return invalid_user(write: true) unless valid_writer?(user)

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          Result.success(subscription_snapshot(user:, resource: topic))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def section_subscription(user:, section_id: nil, section_slug: nil)
          audit("forum.read")
          return invalid_user(write: true) unless valid_writer?(user)

          section, failure = resolve_section(user:, id: section_id, slug: section_slug)
          return failure if failure

          Result.success(subscription_snapshot(user:, resource: section))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def tag_subscription(user:, tag_id: nil, tag_slug: nil)
          audit("forum.read")
          return invalid_user(write: true) unless valid_writer?(user)

          tag, failure = resolve_tag(user:, id: tag_id, slug: tag_slug)
          return failure if failure

          Result.success(subscription_snapshot(user:, resource: tag))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def set_topic_subscription(
          user:, level:, topic_id: nil, topic_public_id: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          level, failure = resolve_subscription_level(level)
          return failure if failure

          topic, failure = resolve_topic(user:, id: topic_id, public_id: topic_public_id)
          return failure if failure

          set_subscription(user:, resource: topic, level:)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def subscribe_topic(level: "watching", **arguments)
          set_topic_subscription(**arguments, level:)
        end

        def unsubscribe_topic(**arguments)
          set_topic_subscription(**arguments, level: "off")
        end

        def set_section_subscription(
          user:, level:, section_id: nil, section_slug: nil
        )
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          level, failure = resolve_subscription_level(level)
          return failure if failure

          section, failure = resolve_section(user:, id: section_id, slug: section_slug)
          return failure if failure

          set_subscription(user:, resource: section, level:)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def subscribe_section(level: "watching", **arguments)
          set_section_subscription(**arguments, level:)
        end

        def unsubscribe_section(**arguments)
          set_section_subscription(**arguments, level: "off")
        end

        def set_tag_subscription(user:, level:, tag_id: nil, tag_slug: nil)
          audit("forum.write")
          return invalid_user(write: true) unless valid_writer?(user)

          level, failure = resolve_subscription_level(level)
          return failure if failure

          tag, failure = resolve_tag(user:, id: tag_id, slug: tag_slug)
          return failure if failure

          set_subscription(user:, resource: tag, level:)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def subscribe_tag(level: "watching", **arguments)
          set_tag_subscription(**arguments, level:)
        end

        def unsubscribe_tag(**arguments)
          set_tag_subscription(**arguments, level: "off")
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end

        def valid_reader?(user)
          user.nil? || valid_writer?(user)
        end

        def valid_writer?(user)
          defined?(::User) && user.is_a?(::User) && user.persisted?
        end

        def invalid_user(write: false)
          message = write ? "a persisted user is required" : "user must be nil or a persisted User"
          Result.failure(code: "invalid_user", error: message)
        end

        def resolve_limit(value)
          limit = Integer(value, exception: false)
          unless limit&.between?(1, MAX_LIMIT)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "limit must be between 1 and #{MAX_LIMIT}"
            ) ]
          end

          [ limit, nil ]
        end

        def resolve_search_query(value)
          query = value.to_s.strip
          unless query.length.between?(1, MAX_SEARCH_LENGTH)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "query must be between 1 and #{MAX_SEARCH_LENGTH} characters"
            ) ]
          end

          [ query, nil ]
        end

        def resolve_search_sort(value)
          sort = value.to_s
          unless SEARCH_SORTS.include?(sort)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "sort must be one of: #{SEARCH_SORTS.join(', ')}"
            ) ]
          end

          [ sort, nil ]
        end

        def resolve_optional_filter(value, name:)
          return [ nil, nil ] if value.nil? || value.to_s.strip.empty?

          normalized = value.to_s.strip
          unless normalized.length <= MAX_FILTER_LENGTH
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "#{name} must be at most #{MAX_FILTER_LENGTH} characters"
            ) ]
          end

          [ normalized, nil ]
        end

        def resolve_search_filters(**values)
          filters = {}
          values.each do |name, value|
            normalized, failure = resolve_optional_filter(value, name: name)
            return [ nil, failure ] if failure

            filters[name] = normalized if normalized
          end
          [ filters, nil ]
        end

        def apply_post_search_filters(relation, filters:, user:)
          if filters[:section]
            section = Community::SectionAccess.scope(
              relation: Community::Section.all,
              user:
            ).find_by(slug: filters[:section])
            return [ relation.none, nil ] unless section

            relation = relation.where(forum_topics: { forum_section_id: section.id })
          end

          if filters[:category]
            category = visible_category_scope(user).find_by(slug: filters[:category])
            return [ relation.none, nil ] unless category

            visible_section_ids = Community::SectionAccess.scope(
              relation: category.sections,
              user:
            ).select(:id)
            relation = relation.where(forum_topics: { forum_section_id: visible_section_ids })
          end

          if filters[:tag]
            tag = Community::Tag.resolve_by_slug_for(filters[:tag], user:)
            return [ relation.none, nil ] unless tag

            relation = relation.joins(topic: :tags).where(forum_tags: { id: tag.id })
          end

          if filters[:author]
            needle = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:author])}%"
            relation = relation.joins(:user).where("users.username ILIKE ?", needle)
          end

          [ relation, nil ]
        end

        def order_post_search(relation, query:, sort:)
          case sort
          when "oldest"
            relation.order("forum_posts.created_at ASC", "forum_posts.id ASC")
          when "relevance"
            quoted_query = ActiveRecord::Base.lease_connection.quote(query)
            relation
              .order(Arel.sql(
                "ts_rank(to_tsvector('simple', coalesce(forum_posts.body, '')), " \
                "plainto_tsquery('simple', #{quoted_query})) DESC"
              ))
              .order("forum_posts.created_at DESC", "forum_posts.id DESC")
          else
            relation.order("forum_posts.created_at DESC", "forum_posts.id DESC")
          end
        end

        def visible_category_scope(user)
          visible_section_ids = Community::SectionAccess.visible_ids(user:)
          Community::Category.where(
            id: Community::Section.where(id: visible_section_ids).select(:forum_category_id)
          )
        end

        def resolve_category(user:, id:, slug:)
          selector, failure = resolve_selector(id:, alternate: slug, alternate_name: "slug")
          return [ nil, failure ] if failure

          relation = visible_category_scope(user)
          category =
            if selector.fetch(:kind) == :id
              relation.find_by(id: selector.fetch(:value))
            else
              relation.find_by(slug: selector.fetch(:value))
            end
          return [ category, nil ] if category

          [ nil, not_found("category") ]
        end

        def resolve_section(user:, id:, slug:)
          selector, failure = resolve_selector(id:, alternate: slug, alternate_name: "slug")
          return [ nil, failure ] if failure

          relation = Community::SectionAccess.scope(
            relation: Community::Section.all,
            user:
          )
          section =
            if selector.fetch(:kind) == :id
              relation.find_by(id: selector.fetch(:value))
            else
              relation.find_by(slug: selector.fetch(:value))
            end
          return [ section, nil ] if section && Community::SectionAccess.view?(section:, user:)

          [ nil, not_found("section") ]
        end

        def resolve_tag(user:, id:, slug:)
          selector, failure = resolve_selector(id:, alternate: slug, alternate_name: "slug")
          return [ nil, failure ] if failure

          tag =
            if selector.fetch(:kind) == :id
              Community::Tag.usable_by(user).find_by(id: selector.fetch(:value))
            else
              Community::Tag.usable_by(user).find_by(slug: selector.fetch(:value))
            end
          effective_tag = tag&.effective_tag
          effective_tag = Community::Tag.usable_by(user).find_by(id: effective_tag.id) if effective_tag
          return [ effective_tag, nil ] if effective_tag

          [ nil, not_found("tag") ]
        end

        def resolve_topic(user:, id:, public_id:)
          selector, failure = resolve_selector(id:, alternate: public_id, alternate_name: "public_id")
          return [ nil, failure ] if failure

          relation = Community::ForumAccess.topic_scope(
            relation: Community::Topic.all,
            user:
          )
          topic =
            if selector.fetch(:kind) == :id
              relation.find_by(id: selector.fetch(:value))
            else
              relation.find_by(public_id: selector.fetch(:value))
            end
          return [ topic, nil ] if topic && Community::ForumAccess.topic_visible?(topic:, user:)

          [ nil, not_found("topic") ]
        end

        def resolve_post(user:, id:)
          numeric_id = positive_id(id)
          unless numeric_id
            return [ nil, Result.failure(code: "invalid_argument", error: "id must be a positive integer") ]
          end

          relation = Community::ForumAccess.post_scope(
            relation: Community::Post.all,
            user:
          )
          post = relation.find_by(id: numeric_id)
          return [ post, nil ] if post && Community::ForumAccess.post_visible?(post:, user:)

          [ nil, not_found("post") ]
        end

        def resolve_deleted_post_for_moderation(user:, id:)
          numeric_id = positive_id(id)
          unless numeric_id
            return [ nil, Result.failure(code: "invalid_argument", error: "id must be a positive integer") ]
          end

          post = Community::Post.with_discarded.find_by(id: numeric_id)
          topic = post&.topic
          if post&.deleted_at.present? &&
              Community::ForumAccess.topic_visible?(topic:, user:) &&
              Community::SectionModeration.can_moderate_topic?(user:, topic:)
            return [ post, nil ]
          end

          [ nil, not_found("post") ]
        end

        def resolve_poll(user:, id:)
          numeric_id = positive_id(id)
          unless numeric_id
            return [ nil, Result.failure(code: "invalid_argument", error: "id must be a positive integer") ]
          end

          poll = Community::Poll.find_by(id: numeric_id)
          return [ poll, nil ] if poll &&
            Community::ForumAccess.topic_visible?(topic: poll.topic, user:)

          [ nil, not_found("poll") ]
        end

        def resolve_attachment(user:, id:)
          numeric_id = positive_id(id)
          unless numeric_id
            return [ nil, Result.failure(code: "invalid_argument", error: "id must be a positive integer") ]
          end

          attachment = Community::PostAttachment.find_by(id: numeric_id)
          if attachment &&
              Community::PostAttachmentAccess.downloadable?(attachment, user:)
            return [ attachment, nil ]
          end

          [ nil, not_found("attachment") ]
        end

        def resolve_optional_post(user:, id:)
          return [ nil, nil ] if id.nil?

          resolve_post(user:, id:)
        end

        def resolve_user(id:, username:)
          selector, failure = resolve_selector(id:, alternate: username, alternate_name: "username")
          return [ nil, failure ] if failure

          user =
            if selector.fetch(:kind) == :id
              ::User.find_by(id: selector.fetch(:value))
            else
              ::User.find_by("LOWER(username) = ?", selector.fetch(:value).downcase)
            end
          return [ user, nil ] if user

          [ nil, not_found("user") ]
        end

        def resolve_optional_future_time(value)
          return [ nil, nil ] if value.nil? || value.to_s.strip.empty?

          time =
            case value
            when Time, DateTime, ActiveSupport::TimeWithZone
              value.to_time
            else
              Time.iso8601(value.to_s)
            end
          unless time > Time.current
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "expires_at must be in the future"
            ) ]
          end

          [ time, nil ]
        rescue ArgumentError
          [ nil, Result.failure(
            code: "invalid_argument",
            error: "expires_at must be an ISO 8601 time"
          ) ]
        end

        def resolve_action(value, allowed:, resource:)
          action = value.to_s
          return [ action, nil ] if allowed.include?(action)

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "#{resource} moderation action must be one of: #{allowed.join(', ')}"
          ) ]
        end

        def resolve_boolean(value, name:)
          return [ value, nil ] if value == true || value == false

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "#{name} must be true or false"
          ) ]
        end

        def resolve_subscription_level(value)
          level = value.to_s
          allowed = Community::Subscription::NOTIFICATION_LEVELS + [ "off" ]
          return [ level, nil ] if allowed.include?(level)

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "level must be one of: #{allowed.join(', ')}"
          ) ]
        end

        def subscription_snapshot(user:, resource:)
          subscription = Community::Subscription.find_by(user:, subscribable: resource)
          Snapshot.subscription_state(
            resource:,
            user:,
            watching: subscription.present?,
            notification_level: subscription&.notification_level
          )
        end

        def serialize_user_mutation(user)
          ::User.transaction do
            ::User.lock.find(user.id)
            yield
          end
        end

        def set_subscription(user:, resource:, level:)
          service_result = serialize_user_mutation(user) do
            Community::SetSubscriptionLevel.call(
              user:,
              subscribable: resource,
              level:
            )
          end
          Result.from_service_result(service_result) do |state|
            Snapshot.subscription_state(
              resource:,
              user:,
              watching: state.fetch(:watching),
              notification_level: state[:notification_level]
            )
          end
        end

        def resolve_selector(id:, alternate:, alternate_name:)
          unless id.nil? ^ alternate.nil?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "provide exactly one of id or #{alternate_name}"
            ) ]
          end

          if id
            numeric_id = positive_id(id)
            unless numeric_id
              return [ nil, Result.failure(code: "invalid_argument", error: "id must be a positive integer") ]
            end
            return [ { kind: :id, value: numeric_id }, nil ]
          end

          value = alternate.to_s
          unless value.length.between?(1, 255)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "#{alternate_name} must be between 1 and 255 characters"
            ) ]
          end

          [ { kind: :alternate, value: }, nil ]
        end

        def positive_id(value)
          id = Integer(value, exception: false)
          id if id&.positive?
        end

        def not_found(resource)
          Result.failure(code: "not_found", error: "#{resource} not found or not visible")
        end

        def visible_snapshots(relation, limit:)
          snapshots = []
          relation.reorder(nil).find_each(batch_size: MAX_LIMIT) do |record|
            snapshot = yield(record)
            snapshots << snapshot if snapshot
            break if snapshots.length >= limit
          end
          snapshots.freeze
        end
      end
    end
  end
end
