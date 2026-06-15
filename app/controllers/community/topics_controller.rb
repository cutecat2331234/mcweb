# frozen_string_literal: true

module Community
  class TopicsController < ApplicationController
    include Community::TopicVisibility
    include Community::TopicListPreloadable
    include Community::SectionTagGroupsSerializable
    include Community::WarningRestrictionsSerializable

    before_action :require_login, only: %i[new create update toggle_subscription toggle_bookmark toggle_mute moderate move merge split mark_solved unsolve update_slow_mode update_auto_close update_auto_open update_auto_bump update_auto_archive mark_unread staff_note reply_ban reply_unban invite close_own reopen_own share_as_pm export]
    before_action :set_section, only: %i[new create]
    before_action :set_topic, only: %i[show update toggle_subscription toggle_bookmark toggle_mute moderate move merge split mark_solved unsolve update_slow_mode update_auto_close update_auto_open update_auto_bump update_auto_archive mark_unread staff_note reply_ban reply_unban invite close_own reopen_own share_as_pm export]

    def show
      @topic.record_view!
      mark_topic_notifications_read!

      posts_scope = if can_moderate_topic?
                      @topic.posts.with_discarded.chronological
      else
                      @topic.posts.chronological
      end
      posts_scope = posts_scope.includes(:user, :quoted_post, :parent_post, :reactions, :edits, :forked_topics, user: { user_badges: :badge })
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

      @pagy, posts = pagy(posts_scope, limit: per_page, page: target_page)
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
          section_prefixes: Array(@topic.section.prefixes),
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
            post_bookmark: post_bookmarks[post.id]
          )
        end,
        pagination: pagy_props(@pagy),
        lastReadFloor: last_read_floor,
        firstUnreadFloor: first_unread_floor,
        markUnreadUrl: logged_in? ? mark_unread_forum_topic_path(@topic) : nil,
        jumpToUnreadUrl: first_unread_floor ? forum_topic_path(@topic, unread: 1) : nil,
        canReply: can_reply_to_topic?,
        cannedResponses: can_moderate_topic? ? Community::CannedResponse.ordered.map { |r| { title: r.title, body: r.body } } : [],
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
        replyDraftUrl: logged_in? ? forum_topic_reply_draft_path(@topic) : nil,
        warningRestrictions: warning_restrictions_props,
        meta: topic_meta_props(@topic)
      }
    end

    def new
      unless @section.allowed?(current_user, :create_topic)
        return redirect_to forum_section_path(@section), alert: "你无权在此分区发帖。"
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
            ip_address: request.remote_ip
          )
          if result.success?
            return redirect_to forum_drafts_path, notice: "主题已定时，将于 #{l(scheduled_at, format: :short)} 发布。"
          end
          return render inertia: "Community/Topics/New",
                        props: { section: section_props },
                        status: :unprocessable_entity,
                        errors: topic_errors(result)
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
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: "主题已创建。"
      else
        render inertia: "Community/Topics/New",
               props: {
                 section: section_props
               },
               status: :unprocessable_entity,
               errors: topic_errors(result)
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
        redirect_to forum_topic_path(@topic), notice: "主题已更新。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def toggle_subscription
      result = Community::ToggleSubscription.call(user: current_user, topic: @topic)

      if result.success?
        notice = if result.value[:watching]
                   case result.value[:notification_level]
                   when "tracking" then "已切换为跟踪（仅站内通知）。"
                   when "normal" then "已切换为普通（仅参与或被提及时通知）。"
                   else "已关注此主题（即时通知）。"
                   end
        else
                   "已取消关注。"
        end
        redirect_to forum_topic_path(@topic), notice: notice
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def toggle_mute
      result = Community::ToggleTopicMute.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: result.value[:muted] ? "已静音此主题。" : "已取消静音。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def toggle_bookmark
      result = Community::ToggleBookmark.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: result.value[:bookmarked] ? "已加入书签。" : "已移除书签。"
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
        redirect_to forum_topic_path(@topic), notice: "主题已更新。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def export
      unless can_moderate_topic?
        return redirect_to forum_topic_path(@topic), alert: "无权导出此主题。"
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
        redirect_to forum_conversation_path(conversation), notice: "主题已通过私信分享。"
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
        redirect_to forum_topic_path(@topic), notice: "主题已关闭。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def reopen_own
      result = Community::CloseOwnTopic.call(user: current_user, topic: @topic, action: "reopen")

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "主题已重新打开。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def move
      section = Community::Section.find_by!(slug: params[:section_slug])
      result = Community::MoveTopic.call(user: current_user, topic: @topic, section: section)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "主题已移动。"
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
        redirect_to forum_topic_path(result.value), notice: "主题已合并。"
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
        redirect_to forum_topic_path(result.value), notice: "主题已拆分。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def mark_solved
      post = @topic.posts.find(params[:post_id])
      result = Community::MarkTopicSolved.call(user: current_user, topic: @topic, post: post)

      if result.success?
        redirect_to forum_topic_path(@topic, anchor: "post-#{post.id}"), notice: "已标记为已解决。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def unsolve
      result = Community::UnsolveTopic.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "已取消已解决标记。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def update_slow_mode
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      seconds = params[:seconds].to_i
      @topic.update!(slow_mode_seconds: seconds.positive? ? seconds : nil)
      redirect_to forum_topic_path(@topic), notice: seconds.positive? ? "慢速模式已启用（#{seconds} 秒）。" : "慢速模式已关闭。"
    end

    def update_auto_close
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      at = params[:auto_close_at].present? ? Time.zone.parse(params[:auto_close_at].to_s) : nil
      @topic.update!(auto_close_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? "主题将于 #{l(at, format: :short)} 自动关闭。" : "自动关闭已取消。"
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: "无效的关闭时间。"
    end

    def update_auto_open
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      at = params[:auto_open_at].present? ? Time.zone.parse(params[:auto_open_at].to_s) : nil
      @topic.update!(auto_open_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? "主题将于 #{l(at, format: :short)} 自动重新开放。" : "自动开放已取消。"
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: "无效的开放时间。"
    end

    def update_auto_bump
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      at = params[:auto_bump_at].present? ? Time.zone.parse(params[:auto_bump_at].to_s) : nil
      @topic.update!(auto_bump_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? "主题将于 #{l(at, format: :short)} 自动提升。" : "自动提升已取消。"
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: "无效的提升时间。"
    end

    def update_auto_archive
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      at = params[:auto_archive_at].present? ? Time.zone.parse(params[:auto_archive_at].to_s) : nil
      @topic.update!(auto_archive_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? "主题将于 #{l(at, format: :short)} 自动归档。" : "自动归档已取消。"
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: "无效的归档时间。"
    end

    def mark_unread
      result = Community::MarkTopicUnread.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "已标记为未读。"
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
        redirect_to forum_topic_path(@topic), notice: "员工备注已添加。"
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
        redirect_to forum_topic_path(@topic), notice: "已禁止 #{user.username} 在此主题回复。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def reply_unban
      user = User.find_by!(username: params[:username])
      result = Community::UnbanTopicReply.call(actor: current_user, topic: @topic, user: user)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "已解除 #{user.username} 的回复限制。"
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
        redirect_to forum_topic_path(@topic), notice: "已邀请 #{params[:username]} 关注此主题。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    private

    def set_section
      @section = Community::Section.find_by!(slug: params[:section_id])
    end

    def set_topic
      @topic = Community::Topic.includes(:section, :user, :tags, :poll, :solved_post, :linked_product).find_by!(public_id: params[:id])
      ensure_topic_visible!(@topic)
    end

    def topic_params
      params.require(:topic).permit(
        :title, :body, :tags, :prefix, :poll_question, :poll_options, :poll_closes_days,
        :poll_multiple_choice, :poll_max_choices, :poll_hide_results_until_vote, :poll_anonymous,
        :scheduled_at, :remove_poll
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
        prefixes: Array(@section.prefixes),
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

    def topic_errors(result)
      errors = {}
      errors[:title] = Array(result.errors[:title]).first if result.errors&.dig(:title)
      errors[:body] = Array(result.errors[:body]).first if result.errors&.dig(:body)
      errors[:title] ||= result.error if result.error.present? && errors.empty?
      errors[:body] ||= result.error if result.error.present? && errors[:title].blank?
      errors
    end

    def mark_topic_read!(posts)
      return unless logged_in?
      return if posts.blank?

      last_floor = posts.map(&:floor_number).max.to_i
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

      types = %w[forum.topic_reply forum.mention forum.section_topic forum.reaction forum.tag_topic forum.followed_topic forum.quote forum.topic_solved]
      current_user.notifications.unread.where(notification_type: types).find_each do |notification|
        topic_id = notification.metadata["topic_id"]
        notification.mark_read! if topic_id == @topic.public_id
      end
    end

    def can_moderate_topic?
      current_user&.permission?("forum.topics.lock")
    end

    def can_invite_topic?
      return false unless current_user

      can_moderate_topic? || current_user.id == @topic.user_id
    end

    def can_move_topic?
      current_user&.permission?("forum.topics.move") || current_user&.permission?("forum.topics.lock")
    end

    def can_edit_topic?
      return false unless current_user

      current_user.id == @topic.user_id || current_user.permission?("forum.topics.lock")
    end

    def can_close_own_topic?
      return false unless current_user
      return false unless SiteSetting.get("forum.allow_op_close", "true") == "true"

      current_user.id == @topic.user_id
    end

    def movable_sections
      Community::Section.ordered.includes(:category).map do |section|
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
      {
        title: topic.title,
        description: description,
        noindex: topic.unlisted?,
        url: "#{request.base_url}#{forum_topic_path(topic)}",
        image: image.presence
      }
    end
  end
end
