# frozen_string_literal: true

module Community
  class TopicsController < ApplicationController
    include Community::TopicVisibility
    include Community::TopicListPreloadable
    include Community::SectionTagGroupsSerializable
    include Community::WarningRestrictionsSerializable
    include Community::SubscriptionNoticeable
    include Community::SectionVisibility

    before_action :require_login, only: %i[new create update toggle_subscription update_subscription toggle_bookmark toggle_mute moderate bulk_moderate move copy merge split mark_solved unsolve update_slow_mode update_auto_close update_auto_open update_auto_bump update_auto_archive mark_unread staff_note reply_ban reply_unban invite close_own reopen_own share_as_pm export]
    before_action :set_section, only: %i[new create]
    before_action :set_topic, only: %i[show update toggle_subscription update_subscription toggle_bookmark toggle_mute moderate move copy merge split mark_solved unsolve update_slow_mode update_auto_close update_auto_open update_auto_bump update_auto_archive mark_unread staff_note reply_ban reply_unban invite close_own reopen_own share_as_pm export]

    def show
      @topic.record_view!
      mark_topic_notifications_read!

      posts_scope = if can_moderate_topic?
                      @topic.posts.with_discarded.chronological
      elsif logged_in?
                      @topic.posts.visible_in_topic(current_user).chronological
      else
                      @topic.posts.published.chronological
      end
      posts_scope = posts_scope.includes(:user, :quoted_post, :parent_post, :reactions, :edits, :forked_topics, :attachments, user: { user_badges: :badge })
      posts_scope = filter_blocked_posts(posts_scope)
      posts_scope = posts_scope.where.not(post_type: "whisper") unless can_moderate_topic?
      posts_scope = case params[:post_sort]
      when "recent" then posts_scope.reorder(floor_number: :desc)
      else posts_scope
      end
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        posts_scope = posts_scope.where("body ILIKE ?", q)
      end

      per_page = 20
      target_post_id = params[:post_id].presence || params[:anchor].to_s.sub(/\Apost-/, "").presence
      target_page = resolve_post_page(posts_scope, target_post_id, per_page: per_page)
      first_unread_floor = logged_in? ? Community::ReadState.first_unread_floor(current_user, @topic) : nil
      if params[:unread] == "1" && first_unread_floor
        target_page = Community::ReadState.page_for_floor(first_unread_floor, per_page: per_page)
      end

      @pagy, posts = pagy(:offset, posts_scope, limit: per_page, page: target_page)
      mark_topic_read!(posts) unless params[:unread] == "1"
      last_read_floor = logged_in? ? Community::ReadState.find_by(user: current_user, topic: @topic)&.last_read_floor.to_i : 0
      topic_bookmark = if logged_in?
                         Community::Bookmark.find_by(user: current_user, topic: @topic, forum_post_id: nil)
      end
      post_bookmarks = if logged_in?
                         Community::Bookmark.where(user: current_user, forum_post_id: posts.map(&:id)).index_by(&:forum_post_id)
      else
                         {}
      end
      verified_purchaser_ids = Commerce::Order
        .where(user_id: posts.map(&:user_id).uniq, status: %w[paid processing fulfilling fulfilled completed])
        .distinct
        .pluck(:user_id)
        .to_set

      render inertia: "Community/Topics/Show", props: {
        topic: serialize_topic_detail(
          @topic,
          watching: watching_topic?,
          notification_level: topic_notification_level,
          muted: muted_topic?,
          bookmarked: bookmarked_topic?,
          can_moderate: can_moderate_topic?,
          can_move: can_move_topic?,
          can_edit: can_edit_topic?,
          viewer: current_user
        ).merge(
          section_prefixes: @topic.section.prefix_options,
          tag_groups: section_tag_groups_for(@topic.section),
          global_announcement: @topic.global_announcement?,
          staff_notes: can_moderate_topic? ? @topic.staff_notes.includes(:author).order(created_at: :desc).map { |note|
            { id: note.id, body: note.body, author: note.author.username, created_at: l(note.created_at, format: :short) }
          } : [],
          staff_note_url: can_moderate_topic? ? staff_note_forum_topic_path(@topic) : nil,
          reply_bans: can_moderate_topic? ? @topic.reply_bans.active.includes(:user).map { |ban|
            { username: ban.user.username, reason: ban.reason, expires_at: ban.expires_at ? l(ban.expires_at, format: :short) : nil }
          } : [],
          can_invite: can_invite_topic?,
          invite_url: can_invite_topic? ? invite_forum_topic_path(@topic) : nil,
          share_as_pm_url: logged_in? ? share_as_pm_forum_topic_path(@topic) : nil,
          export_url: can_moderate_topic? ? export_forum_topic_path(@topic, format: :csv) : nil,
          can_edit_poll: can_edit_topic?
        ),
        posts: posts.map do |post|
          serialize_post(
            post,
            current_user: current_user,
            can_moderate: can_moderate_topic?,
            solved_post_id: @topic.solved_post_id,
            post_bookmark: post_bookmarks[post.id],
            verified_purchaser: verified_purchaser_ids.include?(post.user_id)
          )
        end,
        pagination: pagy_props(@pagy),
        lastReadFloor: last_read_floor,
        firstUnreadFloor: first_unread_floor,
        markUnreadUrl: logged_in? ? mark_unread_forum_topic_path(@topic) : nil,
        jumpToUnreadUrl: first_unread_floor ? forum_topic_path(@topic, unread: 1) : nil,
        canReply: can_reply_to_topic?,
        cannedResponses: can_moderate_topic? ? Community::CannedResponse.ordered.limit(50).map { |r| { title: r.title, body: r.render_for(topic: @topic) } } : [],
        section_read_only: @topic.section.read_only?,
        canMarkSolved: logged_in? && (can_moderate_topic? || current_user.id == @topic.user_id),
        reactionEmojis: Community::ToggleReaction.allowed_emoji,
        sections: can_move_topic? ? movable_sections : [],
        relatedTopics: serialize_topics(@topic.similar_topics),
        reportTopicUrl: logged_in? ? new_forum_report_path(reportable_type: "Community::Topic", reportable_id: @topic.id) : nil,
        poll: @topic.poll ? serialize_poll(@topic.poll) : nil,
        topicSearchQuery: params[:q].to_s,
        postSort: params[:post_sort].to_s.presence || "oldest",
        canCloseOwn: can_close_own_topic?,
        topicBookmark: topic_bookmark ? {
          id: topic_bookmark.id,
          update_url: forum_bookmark_path(topic_bookmark),
          note: topic_bookmark.note,
          remind_at_input: topic_bookmark.remind_at&.strftime("%Y-%m-%dT%H:%M")
        } : nil,
        replyDraft: logged_in? ? Community::ReplyDraft.find_by(user: current_user, topic: @topic)&.body : nil,
        replyDraftAttachments: logged_in? ? reply_draft_attachments_props(@topic) : [],
        replyDraftUrl: logged_in? ? forum_topic_reply_draft_path(@topic) : nil,
        warningRestrictions: warning_restrictions_props,
        subscriptionLevels: Community::SubscriptionLevelOptions.for(:topic),
        subscriptionUrl: logged_in? ? subscription_forum_topic_path(@topic) : nil,
        meta: topic_meta_props(@topic)
      }
    end

    def new
      unless @section.allowed?(current_user, :create_topic)
        return redirect_to forum_section_path(@section), alert: t("mcweb.flash.cannot_post_in_section")
      end

      render inertia: "Community/Topics/New", props: {
        section: section_props,
        similarTitlesUrl: similar_titles_forum_topics_path(section_id: @section.slug),
        warningRestrictions: warning_restrictions_props
      }
    end

    def similar_titles
      section = Community::Section.find_by!(slug: params[:section_id])
      result = Community::FindSimilarTitles.call(section: section, title: params[:title])
      render json: { titles: result.value[:titles] }
    end

    def create
      if topic_params[:scheduled_at].present?
        scheduled_at = Time.zone.parse(topic_params[:scheduled_at].to_s) rescue nil
        if scheduled_at&.> Time.current
          result = Community::ScheduleTopic.call(
            user: current_user,
            section: @section,
            title: topic_params[:title],
            body: topic_params[:body],
            scheduled_at: scheduled_at,
            tag_names: topic_params[:tags],
            prefix: topic_params[:prefix],
            poll_question: topic_params[:poll_question],
            poll_options: parse_poll_options(topic_params[:poll_options]),
            poll_closes_days: topic_params[:poll_closes_days],
            poll_multiple_choice: topic_params[:poll_multiple_choice],
            poll_max_choices: topic_params[:poll_max_choices],
            poll_hide_results_until_vote: topic_params[:poll_hide_results_until_vote],
            ip_address: request.remote_ip,
            attachment_ids: topic_params[:attachment_ids]
          )
          if result.success?
            return redirect_to forum_drafts_path, notice: t("mcweb.flash.topic_scheduled", time: l(scheduled_at, format: :short))
          end
          return render inertia: "Community/Topics/New",
                        props: {
                          section: section_props,
                          warningRestrictions: warning_restrictions_props,
                          form_errors: topic_form_errors(result)
                        },
                        status: :unprocessable_entity
        end
      end

      result = Community::CreateTopic.call(
        user: current_user,
        section: @section,
        title: topic_params[:title],
        body: topic_params[:body],
        tag_names: topic_params[:tags],
        poll_question: topic_params[:poll_question],
        poll_options: parse_poll_options(topic_params[:poll_options]),
        poll_closes_days: topic_params[:poll_closes_days],
        poll_multiple_choice: topic_params[:poll_multiple_choice],
        poll_max_choices: topic_params[:poll_max_choices],
        poll_hide_results_until_vote: topic_params[:poll_hide_results_until_vote],
        poll_anonymous: topic_params[:poll_anonymous],
        prefix: topic_params[:prefix],
        ip_address: request.remote_ip,
        attachment_ids: topic_params[:attachment_ids]
      )

      if result.success?
        notice = result.value.status == "hidden" ? t("mcweb.flash.post_pending_submitted") : t("mcweb.flash.topic_created")
        redirect_to forum_topic_path(result.value), notice: notice
      else
        render inertia: "Community/Topics/New",
               props: {
                 section: section_props,
                 warningRestrictions: warning_restrictions_props,
                 form_errors: topic_form_errors(result)
               },
               status: :unprocessable_entity
      end
    end

    def update
      result = Community::EditTopic.call(
        user: current_user,
        topic: @topic,
        title: topic_params[:title],
        tag_names: topic_params[:tags],
        prefix: topic_params[:prefix],
        poll_params: poll_edit_params
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.topic_updated")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def toggle_subscription
      result = Community::ToggleSubscription.call(user: current_user, topic: @topic)

      if result.success?
        notice = subscription_notice(result.value[:watching], result.value[:notification_level], context: :topic)
        redirect_to forum_topic_path(@topic), notice: notice
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def update_subscription
      result = Community::SetSubscriptionLevel.call(
        user: current_user,
        subscribable: @topic,
        level: params[:level]
      )

      if result.success?
        notice = subscription_notice(result.value[:watching], result.value[:notification_level], context: :topic)
        redirect_after_subscription_update(fallback_location: forum_topic_path(@topic), notice: notice)
      else
        redirect_after_subscription_update(fallback_location: forum_topic_path(@topic), alert: result.error || t("mcweb.flash.subscription_update_failed"))
      end
    end

    def toggle_mute
      result = Community::ToggleTopicMute.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: result.value[:muted] ? t("mcweb.flash.topic_muted") : t("mcweb.flash.topic_unmuted")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def toggle_bookmark
      result = Community::ToggleBookmark.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: result.value[:bookmarked] ? t("mcweb.flash.bookmark_added") : t("mcweb.flash.bookmark_removed")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def moderate
      result = Community::ModerateTopic.call(
        user: current_user,
        topic: @topic,
        action: params[:action_type],
        lock_reason: params[:lock_reason],
        assignee_username: params[:assignee_username]
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.topic_updated")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def bulk_moderate
      unless Community::SectionModeration.bulk_moderate_authorized?(user: current_user)
        return redirect_back fallback_location: forum_latest_path, alert: t("mcweb.flash.cannot_moderate_bulk")
      end

      result = Community::BulkModerateTopics.call(
        user: current_user,
        topic_public_ids: params[:topic_ids],
        action: params[:action_type],
        lock_reason: params[:lock_reason]
      )

      if result.success?
        notice = t("mcweb.flash.bulk_moderate_processed", count: result.value[:moderated])
        notice += t("mcweb.flash.bulk_moderate_failed_suffix", count: result.value[:failed]) if result.value[:failed].positive?
        redirect_to bulk_moderate_destination, notice: notice
      else
        redirect_to bulk_moderate_destination, alert: result.error || t("mcweb.flash.operation_failed")
      end
    end

    def export
      unless can_moderate_topic?
        return redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.cannot_export_topic")
      end

      result = Community::ExportTopicPosts.call(topic: @topic)
      send_data result.value[:csv], filename: "topic-#{@topic.public_id}.csv", type: "text/csv", disposition: "attachment"
    end

    def share_as_pm
      result = Community::ShareTopicAsConversation.call(
        sender: current_user,
        topic: @topic,
        recipient_username: params[:recipient_username],
        message: params[:message]
      )

      if result.success?
        conversation = result.value[:conversation]
        redirect_to forum_conversation_path(conversation), notice: t("mcweb.flash.topic_shared_pm")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def close_own
      result = Community::CloseOwnTopic.call(
        user: current_user,
        topic: @topic,
        action: "close",
        lock_reason: params[:lock_reason]
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.topic_closed")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def reopen_own
      result = Community::CloseOwnTopic.call(user: current_user, topic: @topic, action: "reopen")

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.topic_reopened")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def move
      section = Community::Section.find_by!(slug: params[:section_slug])
      leave_redirect = ActiveModel::Type::Boolean.new.cast(params[:leave_redirect])
      result = Community::MoveTopic.call(
        user: current_user,
        topic: @topic,
        section: section,
        leave_redirect: leave_redirect
      )

      if result.success?
        notice = leave_redirect ? t("mcweb.flash.topic_moved_with_redirect") : t("mcweb.flash.topic_moved")
        redirect_to forum_topic_path(@topic), notice: notice
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def copy
      section = Community::Section.find_by!(slug: params[:section_slug])
      result = Community::CopyTopic.call(user: current_user, topic: @topic, section: section)

      if result.success?
        redirect_to forum_topic_path(result.value), notice: t("mcweb.flash.topic_copied")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def merge
      result = Community::MergeTopics.call(
        user: current_user,
        source: @topic,
        target_public_id: params[:target_topic_id]
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: t("mcweb.flash.topic_merged")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def split
      post = @topic.posts.find(params[:post_id])
      section = params[:section_slug].present? ? Community::Section.find_by(slug: params[:section_slug]) : nil
      result = Community::SplitTopic.call(
        user: current_user,
        topic: @topic,
        post: post,
        title: params[:title],
        section: section
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: t("mcweb.flash.topic_split")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def mark_solved
      post = @topic.posts.find(params[:post_id])
      result = Community::MarkTopicSolved.call(user: current_user, topic: @topic, post: post)

      if result.success?
        redirect_to forum_topic_path(@topic, anchor: "post-#{post.id}"), notice: t("mcweb.flash.topic_marked_solved")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def unsolve
      result = Community::UnsolveTopic.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.topic_unmarked_solved")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def update_slow_mode
      return redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.cannot_moderate") unless can_moderate_topic?

      seconds = params[:seconds].to_i
      @topic.update!(slow_mode_seconds: seconds.positive? ? seconds : nil)
      redirect_to forum_topic_path(@topic), notice: seconds.positive? ? t("mcweb.flash.slow_mode_enabled", seconds: seconds) : t("mcweb.flash.slow_mode_disabled")
    end

    def update_auto_close
      return redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.cannot_moderate") unless can_moderate_topic?

      at = params[:auto_close_at].present? ? Time.zone.parse(params[:auto_close_at].to_s) : nil
      @topic.update!(auto_close_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? t("mcweb.flash.auto_close_scheduled", time: l(at, format: :short)) : t("mcweb.flash.auto_close_cancelled")
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.invalid_close_time")
    end

    def update_auto_open
      return redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.cannot_moderate") unless can_moderate_topic?

      at = params[:auto_open_at].present? ? Time.zone.parse(params[:auto_open_at].to_s) : nil
      @topic.update!(auto_open_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? t("mcweb.flash.auto_open_scheduled", time: l(at, format: :short)) : t("mcweb.flash.auto_open_cancelled")
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.invalid_open_time")
    end

    def update_auto_bump
      return redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.cannot_moderate") unless can_moderate_topic?

      at = params[:auto_bump_at].present? ? Time.zone.parse(params[:auto_bump_at].to_s) : nil
      @topic.update!(auto_bump_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? t("mcweb.flash.auto_pin_scheduled", time: l(at, format: :short)) : t("mcweb.flash.auto_pin_cancelled")
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.invalid_pin_time")
    end

    def update_auto_archive
      return redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.cannot_moderate") unless can_moderate_topic?

      at = params[:auto_archive_at].present? ? Time.zone.parse(params[:auto_archive_at].to_s) : nil
      @topic.update!(auto_archive_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? t("mcweb.flash.auto_archive_scheduled", time: l(at, format: :short)) : t("mcweb.flash.auto_archive_cancelled")
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: t("mcweb.flash.invalid_archive_time")
    end

    def mark_unread
      result = Community::MarkTopicUnread.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.topic_marked_unread")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def staff_note
      result = Community::CreateTopicStaffNote.call(
        actor: current_user,
        topic: @topic,
        body: params[:body]
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.staff_note_added")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def reply_ban
      user = User.find_by!(username: params[:username])
      expires_at = params[:expires_days].present? ? params[:expires_days].to_i.days.from_now : nil
      result = Community::BanTopicReply.call(
        actor: current_user,
        topic: @topic,
        user: user,
        reason: params[:reason],
        expires_at: expires_at
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.user_reply_banned", username: user.username)
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def reply_unban
      user = User.find_by!(username: params[:username])
      result = Community::UnbanTopicReply.call(actor: current_user, topic: @topic, user: user)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.user_reply_unbanned", username: user.username)
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def invite
      result = Community::InviteTopicWatcher.call(
        inviter: current_user,
        topic: @topic,
        username: params[:username]
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: t("mcweb.flash.user_invited_watch", username: params[:username])
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    private

    def set_section
      @section = Community::Section.find_by!(slug: params[:section_id])
      ensure_section_visible!(@section)
    end

    def set_topic
      @topic = Community::Topic.includes(:section, :user, :tags, :poll, :solved_post, :linked_product).find_by!(public_id: params[:id])
      ensure_topic_visible!(@topic)
      ensure_section_visible!(@topic.section)
    end

    def topic_params
      params.require(:topic).permit(
        :title, :body, :tags, :prefix, :poll_question, :poll_options, :poll_closes_days,
        :poll_multiple_choice, :poll_max_choices, :poll_hide_results_until_vote, :poll_anonymous,
        :scheduled_at, :remove_poll, attachment_ids: []
      )
    end

    def poll_edit_params
      return nil unless params[:topic].key?(:poll_question) || params[:topic].key?(:poll_options) || params[:topic][:remove_poll].present?

      {
        poll_question: topic_params[:poll_question],
        poll_options: parse_poll_options(topic_params[:poll_options]),
        poll_closes_days: topic_params[:poll_closes_days],
        poll_multiple_choice: topic_params[:poll_multiple_choice],
        poll_max_choices: topic_params[:poll_max_choices],
        poll_hide_results_until_vote: topic_params[:poll_hide_results_until_vote],
        remove_poll: topic_params[:remove_poll]
      }
    end

    def section_props
      {
        name: @section.name,
        slug: @section.slug,
        url: forum_section_path(@section),
        prefixes: @section.prefix_options,
        prefix_required: @section.prefix_required?,
        topic_template: @section.topic_template,
        required_tags: @section.required_tags.map { |tag| { name: tag.name, slug: tag.slug, url: forum_tag_path(tag.slug) } },
        required_tag_groups: @section.required_tag_groups.map { |g| { name: g.name, slug: g.slug } },
        tag_groups: section_tag_groups_for(@section),
        allowed_tags: @section.allowed_tags.map { |tag| { name: tag.name, slug: tag.slug, url: forum_tag_path(tag.slug) } },
        default_tags: @section.default_tags.map { |tag| tag.name }
      }
    end

    def parse_poll_options(raw)
      raw.to_s.lines.map(&:strip).reject(&:blank?)
    end

    def topic_form_errors(result)
      inertia_form_errors(result, prefix: "topic")
    end

    def mark_topic_read!(posts)
      return unless logged_in?

      countable = posts.select { |post| post.published? && post.post_type_regular? }
      return if countable.blank?

      last_floor = countable.map(&:floor_number).max.to_i
      Community::ReadState.mark_read!(current_user, @topic, floor: last_floor)
    end

    def watching_topic?
      return false unless logged_in?

      Community::Subscription.exists?(user: current_user, subscribable: @topic)
    end

    def topic_notification_level
      return nil unless logged_in?

      Community::Subscription.find_by(user: current_user, subscribable: @topic)&.notification_level
    end

    def can_reply_to_topic?
      return false unless logged_in?
      return false if @topic.locked?
      return false unless @topic.section.allowed?(current_user, :reply)
      return false unless @topic.section.trust_allowed?(current_user, :reply)
      return false if Community::TopicReplyBan.active.exists?(forum_topic_id: @topic.id, user_id: current_user.id)

      return false unless @topic.section.writable_by?(current_user, :reply)

      true
    end

    def bookmarked_topic?
      return false unless logged_in?

      Community::Bookmark.exists?(user: current_user, topic: @topic)
    end

    def muted_topic?
      return false unless logged_in?

      Community::TopicMute.exists?(user: current_user, topic: @topic)
    end

    def mark_topic_notifications_read!
      return unless logged_in?

      types = %w[forum.topic_reply forum.mention forum.section_topic forum.reaction forum.tag_topic forum.followed_topic forum.followed_reply forum.quote forum.topic_solved]
      current_user.notifications.unread.where(notification_type: types).find_each do |notification|
        topic_id = notification.metadata["topic_id"]
        notification.mark_read! if topic_id == @topic.public_id
      end
    end

    def can_moderate_topic?
      Community::SectionModeration.can_moderate_topic?(user: current_user, topic: @topic)
    end

    def can_invite_topic?
      return false unless current_user

      can_moderate_topic? || current_user.id == @topic.user_id
    end

    def can_move_topic?
      return false unless current_user

      Community::SectionModeration.can_move_topic?(user: current_user, topic: @topic)
    end

    def can_edit_topic?
      Community::SectionModeration.can_edit_topic?(user: current_user, topic: @topic)
    end

    def can_close_own_topic?
      return false unless current_user
      return false unless SiteSetting.get("forum.allow_op_close", "true") == "true"

      current_user.id == @topic.user_id
    end

    def movable_sections
      Community::SectionModeration.moderated_sections_for(current_user)
        .ordered
        .includes(:category)
        .map do |section|
        { slug: section.slug, name: section.name, category: section.category&.name }
      end
    end

    def resolve_post_page(posts_scope, post_id, per_page:)
      return params[:page].to_i if params[:page].present? && params[:page].to_i.positive?
      return 1 if post_id.blank?

      post = posts_scope.find_by(id: post_id)
      return 1 unless post

      Community::ReadState.page_for_floor(post.floor_number, per_page: per_page)
    end

    def topic_meta_props(topic)
      first_post = topic.posts.first
      description = first_post&.body&.truncate(160)
      image = first_post&.body.to_s[/!\[[^\]]*\]\(([^)]+)\)/, 1]
      meta = {
        title: topic.title,
        description: description,
        noindex: topic.unlisted?,
        url: "#{request.base_url}#{forum_topic_path(topic)}",
        image: image.presence
      }

      if (poll = topic.poll)
        meta[:title] = "#{topic.title} — #{t('mcweb.forum.poll_meta.title_suffix')}"
        meta[:description] = "#{t('mcweb.forum.poll_meta.description_prefix')}#{poll.question}"
        meta[:url] = "#{request.base_url}#{forum_topic_path(topic)}#poll"
        meta[:poll_question] = poll.question
        meta[:twitter_card] = "summary"
        meta[:twitter_title] = meta[:title]
        meta[:twitter_description] = meta[:description]
        meta[:og_locale] = "zh_CN"
        meta[:og_site_name] = "Mcweb"
      end

      meta
    end

    def bulk_moderate_destination
      safe_local_path(params[:return_to]) || safe_referer_path(fallback: forum_latest_path)
    end

    def reply_draft_attachments_props(topic)
      draft = Community::ReplyDraft.find_by(user: current_user, topic: topic)
      ids = draft&.attachment_id_list || []
      return [] if ids.empty?

      Community::PostAttachment.unlinked.where(user: current_user, id: ids).filter_map do |attachment|
        next unless attachment.file.attached?

        {
          id: attachment.id,
          filename: attachment.filename,
          human_size: attachment.human_size,
          download_url: forum_attachment_path(attachment)
        }
      end
    end
  end
end
