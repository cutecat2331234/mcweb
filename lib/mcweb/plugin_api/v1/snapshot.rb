# frozen_string_literal: true

require_relative "normalizer"

module Mcweb
  module PluginApi
    module V1
      # Explicit allow-list serializers for user-authorized forum resources.
      # Keeping these separate from model serializers makes the SDK contract
      # stable and prevents accidental exposure when model columns are added.
      module Snapshot
        SCHEMA_VERSION = "1"

        module_function

        def category(category)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.category",
            id: category.id,
            name: category.name,
            slug: category.slug,
            position: category.position,
            color_hex: category.color_hex,
            icon: category.icon,
            created_at: category.created_at,
            updated_at: category.updated_at
          )
        end

        def section(section)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.section",
            id: section.id,
            category_id: section.forum_category_id,
            parent_id: section.parent_id,
            name: section.name,
            slug: section.slug,
            position: section.position,
            login_required: section.login_required?,
            read_only: section.read_only?
          )
        end

        def tag(tag)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.tag",
            id: tag.id,
            canonical_tag_id: tag.canonical_tag_id,
            name: tag.name,
            slug: tag.slug,
            description: tag.description,
            color_hex: tag.color_hex,
            staff_only: tag.staff_only?,
            created_at: tag.created_at,
            updated_at: tag.updated_at
          )
        end

        def topic(topic)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.topic",
            id: topic.id,
            public_id: topic.public_id,
            section_id: topic.forum_section_id,
            user_id: topic.user_id,
            title: topic.title,
            prefix: topic.prefix,
            status: topic.status,
            unlisted: topic.unlisted?,
            locked: topic.locked?,
            pinned: topic.pinned?,
            pinned_until: topic.pinned_until,
            featured: topic.featured?,
            wiki: topic.wiki?,
            global_announcement: topic.global_announcement?,
            assigned_to_id: topic.assigned_to_id,
            solved_post_id: topic.solved_post_id,
            redirect_to_topic_id: topic.redirect_to_topic_id,
            archived_at: topic.archived_at,
            deleted_at: topic.deleted_at,
            replies_count: topic.replies_count,
            views_count: topic.views_count,
            last_posted_at: topic.last_posted_at,
            created_at: topic.created_at,
            updated_at: topic.updated_at
          )
        end

        def post(post)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.post",
            id: post.id,
            topic_id: post.forum_topic_id,
            user_id: post.user_id,
            quoted_post_id: post.quoted_post_id,
            parent_post_id: post.parent_post_id,
            floor_number: post.floor_number,
            body: post.body,
            status: post.status,
            post_type: post.post_type,
            wiki: post.wiki_post?,
            staff_notice: post.staff_notice,
            edited_at: post.edited_at,
            deleted_at: post.deleted_at,
            created_at: post.created_at,
            updated_at: post.updated_at
          )
        end

        def poll(poll, user:)
          viewer_vote_indices =
            if user
              poll.votes.where(user: user).order(:option_index).pluck(:option_index)
            else
              []
            end
          show_results =
            !poll.hide_results_until_vote? ||
            viewer_vote_indices.any? ||
            !poll.open?
          results = show_results ? poll.results : []

          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.poll",
            id: poll.id,
            topic_id: poll.forum_topic_id,
            question: poll.question,
            options: poll.options.each_with_index.map { |label, index| { label:, index: } },
            open: poll.open?,
            multiple_choice: poll.multiple_choice?,
            max_choices: poll.max_choices,
            hide_results_until_vote: poll.hide_results_until_vote?,
            anonymous: poll.anonymous?,
            show_results: show_results,
            results: results,
            total_votes: show_results ? poll.total_votes : nil,
            viewer_vote_indices: viewer_vote_indices,
            closes_at: poll.closes_at,
            created_at: poll.created_at,
            updated_at: poll.updated_at
          )
        end

        def topic_field_definition(definition, editable:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.topic_field_definition",
            key: definition.key,
            label: definition.label,
            description: definition.description,
            field_type: definition.field_type,
            choices: definition.choice_list,
            required: definition.required?,
            display_location: definition.display_location,
            owner_plugin_id: definition.owner_plugin_id,
            editable: editable
          )
        end

        def topic_field(topic:, serialized:)
          Normalizer.call(
            {
              schema_version: SCHEMA_VERSION,
              type: "forum.topic_field",
              topic_id: topic.id
            }.merge(serialized)
          )
        end

        def attachment(attachment)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.attachment",
            id: attachment.id,
            post_id: attachment.forum_post_id,
            user_id: attachment.user_id,
            filename: attachment.filename,
            content_type: attachment.content_type,
            byte_size: attachment.byte_size,
            download_count: attachment.download_count,
            linked: attachment.linked?,
            created_at: attachment.created_at,
            updated_at: attachment.updated_at
          )
        end

        def attachment_sync(post:, service_state:, attachments:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.attachment_sync",
            post_id: post.id,
            linked: service_state.fetch(:linked),
            unlinked: service_state.fetch(:unlinked),
            changed: service_state.fetch(:changed),
            attachments: attachments
          )
        end

        def topic_staff_note(note)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.topic_staff_note",
            id: note.id,
            topic_id: note.forum_topic_id,
            author_id: note.author_id,
            body: note.body,
            created_at: note.created_at,
            updated_at: note.updated_at
          )
        end

        def topic_invite(invite)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.topic_invite",
            id: invite.id,
            topic_id: invite.forum_topic_id,
            user_id: invite.user_id,
            invited_by_id: invite.invited_by_id,
            created_at: invite.created_at,
            updated_at: invite.updated_at
          )
        end

        def topic_reply_ban(ban)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.topic_reply_ban",
            id: ban.id,
            topic_id: ban.forum_topic_id,
            user_id: ban.user_id,
            created_by_id: ban.created_by_id,
            reason: ban.reason,
            expires_at: ban.expires_at,
            active: ban.active?,
            created_at: ban.created_at,
            updated_at: ban.updated_at
          )
        end

        def topic_reply_ban_state(topic:, user:, banned:, ban: nil)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.topic_reply_ban_state",
            topic_id: topic.id,
            user_id: user.id,
            banned: banned,
            ban: ban && topic_reply_ban(ban)
          )
        end

        def reaction_type(emoji:, name:, score:, position:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.reaction_type",
            emoji: emoji,
            name: name,
            score: score,
            position: position
          )
        end

        def reaction_summary(post:, user:, counts:, viewer_emojis:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.reaction_summary",
            post_id: post.id,
            topic_id: post.forum_topic_id,
            viewer_user_id: user&.id,
            counts: counts,
            viewer_emojis: viewer_emojis
          )
        end

        def reaction_state(post:, user:, emoji:, added:, counts:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.reaction_state",
            post_id: post.id,
            topic_id: post.forum_topic_id,
            user_id: user.id,
            emoji: emoji,
            added: added,
            counts: counts
          )
        end

        def bookmark_state(resource:, user:, bookmarked:)
          resource_type, resource_id, topic_id =
            case resource
            when Community::Topic
              [ "topic", resource.id, resource.id ]
            when Community::Post
              [ "post", resource.id, resource.forum_topic_id ]
            else
              raise ArgumentError, "unsupported bookmark resource"
            end

          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.bookmark_state",
            resource_type: resource_type,
            resource_id: resource_id,
            topic_id: topic_id,
            user_id: user.id,
            bookmarked: bookmarked
          )
        end

        def subscription_state(resource:, user:, watching:, notification_level:)
          resource_type =
            case resource
            when Community::Topic then "topic"
            when Community::Section then "section"
            when Community::Tag then "tag"
            else raise ArgumentError, "unsupported subscription resource"
            end

          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "forum.subscription_state",
            resource_type: resource_type,
            resource_id: resource.id,
            user_id: user.id,
            watching: watching,
            notification_level: notification_level
          )
        end
      end
    end
  end
end
