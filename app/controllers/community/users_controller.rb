# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    include Community::TopicListPreloadable

    before_action :require_login, only: %i[update]

    def card
      user = User.active.find_by!(username: params[:id])
      trust = Community::TrustLevel.level_info(user)
      posts_count = Community::Post.where(user: user, status: :published).count
      badges = user.user_badges.includes(:badge).order(granted_at: :desc).limit(3).map do |ub|
        {
          name: ub.badge.name,
          icon: ub.badge.icon,
          color: ub.badge.color,
          granted_at: l(ub.granted_at, format: :short)
        }
      end
      memberships = Commerce::SerializeUserMemberships.for_user(user, limit: 3)
      likes_received = Community::Reaction.joins(:post).where(forum_posts: { user_id: user.id }).count
      following = logged_in? && current_user.id != user.id && Community::UserFollow.exists?(follower: current_user, followed: user)
      ingame = Minecraft::IngameStatusForUser.call(user: user)
      ingame_data = ingame.success? ? ingame.value : {}

      render json: {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        trust_level: trust[:level],
        trust_name: trust[:name],
        posts_count: posts_count,
        likes_received: likes_received,
        bio: user.bio.presence,
        member_since: l(user.created_at, format: :short),
        last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil,
        online: user.last_seen_at.present? && user.last_seen_at > 5.minutes.ago,
        badges: badges,
        memberships: memberships,
        message_url: (logged_in? && current_user.id != user.id && Community::TrustLevel.can_send_pm?(current_user)) ? new_forum_conversation_path(to: user.username) : nil,
        follow_url: (logged_in? && current_user.id != user.id) ? forum_user_follow_path(user.username) : nil,
        following: following,
        ingame_online: ingame_data[:ingame_online] == true,
        ingame_server: ingame_data[:ingame_server],
        last_seen_ingame_at: ingame_data[:last_seen_ingame_at]
      }
    end

    def show
      user = User.find_by!(username: params[:id])
      tab = params[:tab].to_s.in?(%w[topics posts store assigned minecraft]) ? params[:tab] : "topics"
      topics_scope = if logged_in? && (current_user.id == user.id || current_user.permission?("forum.topics.lock"))
                       Community::Topic.where(user: user, status: :published)
      else
                       Community::Topic.where(user: user, status: :published, unlisted: false)
      end.merge(Community::Topic.accessible_by(current_user)).order(created_at: :desc)
      posts_scope = Community::Post.where(user: user, status: :published).joins(:topic)
      posts_scope = if logged_in? && (current_user.id == user.id || current_user.permission?("forum.topics.lock"))
                      posts_scope.where(forum_topics: { status: :published })
      else
                      posts_scope.where(forum_topics: { status: :published, unlisted: false })
      end
      posts_scope = posts_scope.merge(Community::Topic.accessible_by(current_user))
      posts_scope = posts_scope.includes(:topic).order(created_at: :desc)
      posts_count = posts_scope.count
      @pagy_topics, topics = pagy(:offset, preload_topics(topics_scope), limit: 20, page: [ params[:topics_page].to_i, 1 ].max)
      @pagy_posts, posts = pagy(:offset, posts_scope, limit: 20, page: [ params[:posts_page].to_i, 1 ].max)
      assigned_scope = Community::Topic.published_listed.accessible_by(current_user).where(assigned_to: user).order(last_posted_at: :desc)
      @pagy_assigned, assigned_topics = pagy(:offset, preload_topics(assigned_scope), limit: 20, page: [ params[:assigned_page].to_i, 1 ].max)
      trust = Community::TrustLevel.level_info(user)
      progress = Community::TrustLevel.progress_for(user)
      liked_rows = Community::Post.where(user: user, status: :published)
        .joins(:topic)
        .merge(Community::Topic.where(status: :published, unlisted: false).accessible_by(current_user))
        .joins(:reactions)
        .group("forum_posts.id")
        .order(Arel.sql("COUNT(forum_reactions.id) DESC"))
        .limit(10)
        .pluck(Arel.sql("forum_posts.id"), Arel.sql("COUNT(forum_reactions.id)"))

      liked_counts = liked_rows.to_h
      liked_posts = Community::Post.where(id: liked_counts.keys)
        .includes(:topic)
        .sort_by { |post| -liked_counts[post.id].to_i }
        .map do |post|
          {
            id: post.id,
            body: post.body.truncate(100),
            floor_number: post.floor_number,
            topic_title: post.topic.title,
            topic_url: forum_topic_path(post.topic),
            likes_count: liked_counts[post.id].to_i
          }
        end

      store_reviews = Commerce::Review.published.where(user: user).includes(:product).order(created_at: :desc).limit(10).map do |review|
        {
          id: review.id,
          product_name: review.product.name,
          product_url: store_product_path(review.product),
          rating: review.rating,
          body: review.body&.truncate(120),
          created_at: l(review.created_at, format: :short)
        }
      end
      orders_count = Commerce::Order.where(user: user, status: %w[paid processing fulfilling fulfilled completed]).count
      store_orders = if logged_in? && current_user.id == user.id
                       Commerce::Order.where(user: user, status: %w[paid processing fulfilling fulfilled completed])
                         .order(created_at: :desc).limit(10).map do |order|
                         {
                           order_number: order.order_number,
                           status_label: order_status_label(order.status),
                           total_label: format_money(order.total_cents, order.currency),
                           url: store_order_path(order),
                           created_at: l(order.created_at, format: :short)
                         }
                       end
      else
                       []
      end

      render inertia: "Community/Users/Show", props: {
        profile: {
          username: user.username,
          display_name: user.display_name,
          forum_title: user.forum_title,
          forum_flair_color_hex: user.forum_flair_color_hex,
          avatar_url: user.avatar_url,
          bio: user.bio,
          trust_level: trust[:level],
          trust_name: trust[:name],
          likes_received: Community::Reaction.joins(:post).where(forum_posts: { user_id: user.id }).count,
          member_since: l(user.created_at, format: :long),
          last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil,
          online: user.last_seen_at && user.last_seen_at > 5.minutes.ago,
          forum_signature: user.forum_signature,
          topics_count: topics_scope.count,
          posts_count: posts_count,
          orders_count: orders_count,
          assigned_count: assigned_scope.count,
          followers_count: Community::UserFollow.where(followed: user).count,
          followers_url: forum_user_followers_path(user.username),
          profile_url: forum_user_path(user.username),
          message_url: logged_in? && current_user.id != user.id ? new_forum_conversation_path(to: user.username) : nil,
          block_url: logged_in? && current_user.id != user.id ? forum_block_user_path(user.username) : nil,
          ignore_url: logged_in? && current_user.id != user.id ? forum_ignore_user_path(user.username) : nil,
          report_url: (logged_in? && current_user.id != user.id) ? new_forum_report_path(reportable_type: "User", reportable_id: user.id) : nil,
          is_blocked: logged_in? && current_user.id != user.id && Community::UserBlock.exists?(blocker: current_user, blocked: user),
          is_ignored: logged_in? && current_user.id != user.id && Community::UserIgnore.exists?(ignorer: current_user, ignored: user),
          is_muted: logged_in? && current_user.id == user.id && Community::Mute.muted?(user),
          mute_info: mute_info_for(user),
          can_edit: logged_in? && current_user.id == user.id,
          is_following: logged_in? && current_user.id != user.id && Community::UserFollow.exists?(follower: current_user, followed: user),
          follow_url: logged_in? && current_user.id != user.id ? forum_user_follow_path(user.username) : nil,
          trust_progress: progress,
          warning_points: (logged_in? && (current_user.id == user.id || current_user.permission?("forum.users.warn") || current_user.permission?("admin.access"))) ? Community::UserWarning.total_points_for(user) : nil,
          store_credit_label: (logged_in? && current_user.id == user.id && user.store_credit_cents.to_i.positive?) ? format_money(user.store_credit_cents.to_i, "CNY") : nil,
          store_wallet_url: (logged_in? && current_user.id == user.id) ? store_wallet_path : nil
        },
        warnings: (logged_in? && (current_user.id == user.id || current_user.permission?("forum.users.warn") || current_user.permission?("admin.access"))) ? user.forum_warnings.recent.limit(10).map do |warning|
          {
            reason: warning.reason,
            points: warning.points,
            issuer: warning.issuer.username,
            created_at: l(warning.created_at, format: :short),
            expires_at: warning.expires_at ? l(warning.expires_at, format: :short) : nil,
            expired: warning.expired?
          }
        end : [],
        badges: user.user_badges.includes(:badge).order(granted_at: :desc).map do |ub|
          {
            name: ub.badge.name,
            slug: ub.badge.slug,
            icon: ub.badge.icon,
            description: ub.badge.description,
            color: ub.badge.color,
            granted_at: l(ub.granted_at, format: :short),
            url: forum_badge_path(ub.badge.slug)
          }
        end,
        topics: serialize_topics(topics),
        topicsPagination: pagy_props(@pagy_topics),
        assigned_topics: serialize_topics(assigned_topics),
        assignedPagination: pagy_props(@pagy_assigned),
        recent_posts: posts.map do |post|
          {
            id: post.id,
            body: post.body.truncate(120),
            floor_number: post.floor_number,
            topic_title: post.topic.title,
            topic_url: forum_topic_path(post.topic),
            created_at: l(post.created_at, format: :short)
          }
        end,
        postsPagination: pagy_props(@pagy_posts),
        activeTab: tab,
        liked_posts: liked_posts,
        store_reviews: store_reviews,
        store_orders: store_orders,
        account_type: account_type_label(user.account_type),
        role_names: user.roles.order(:name).pluck(:name),
        game_permission_groups: serialize_game_permission_groups(user),
        memberships: Commerce::SerializeUserMemberships.for_user(user),
        minecraft: serialize_minecraft_profile(user),
        skin_mode: SiteSetting.get("minecraft.profile.skin_mode", "2d"),
        profile_sections: SiteSetting.get("minecraft.profile.sections", "minecraft,trust,roles,game_groups").to_s.split(",").map(&:strip).reject(&:blank?),
        custom_fields: Community::SerializeUserFields.for(user: user, viewer: current_user),
        profile_wall: profile_wall_props(user),
        profile_posts: serialize_profile_posts(user)
      }
    end

    def update
      user = User.find_by!(username: params[:id])
      return head :forbidden unless current_user.id == user.id

      if ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remove_forum_avatar))
        remove_forum_avatar!(user)
        redirect_to forum_user_path(user.username), notice: t("mcweb.flash.avatar_reset")
        return
      end

      if params.dig(:user, :forum_avatar).present?
        error = attach_forum_avatar!(user, file: params[:user][:forum_avatar])
        if error
          redirect_to forum_user_path(user.username), alert: error
        else
          redirect_to forum_user_path(user.username), notice: t("mcweb.flash.avatar_updated")
        end
        return
      end

      if user.update(user_params)
        field_result = Community::SyncUserFieldValues.call(
          user: user,
          values: params[:user_fields].present? ? params[:user_fields].to_unsafe_h : {},
          context: :profile
        )
        unless field_result.success?
          redirect_to forum_user_path(user.username), alert: field_result.errors.values.join(" ")
          return
        end
        redirect_to forum_user_path(user.username), notice: t("mcweb.flash.profile_updated")
      else
        redirect_to forum_user_path(user.username), alert: user.errors.full_messages.to_sentence
      end
    end

    private

    def user_params
      params.require(:user).permit(:bio, :forum_title, :forum_signature, :forum_flair_color_hex)
    end

    def attach_forum_avatar!(user, file:)
      return t("mcweb.services.errors.avatar_file_required") unless file.respond_to?(:content_type)

      allowed = %w[image/jpeg image/png image/gif image/webp]
      return t("mcweb.services.errors.avatar_unsupported_format") unless allowed.include?(file.content_type)
      return t("mcweb.services.errors.avatar_too_large") if file.size > 2.megabytes

      user.forum_avatar.attach(file)
      nil
    end

    def remove_forum_avatar!(user)
      user.forum_avatar.purge if user.forum_avatar.attached?
    end

    def mute_info_for(user)
      return nil unless logged_in? && current_user.id == user.id
      return nil unless Community::Mute.muted?(user)

      mute = Community::Mute.active.where(user: user).includes(:section).order(created_at: :desc).first
      return nil unless mute

      {
        section: mute.section&.name || t("mcweb.forum.mute.site_wide"),
        reason: mute.reason,
        expires_at: mute.expires_at ? l(mute.expires_at, format: :short) : t("mcweb.forum.mute.permanent")
      }
    end

    def account_type_label(account_type)
      I18n.t("mcweb.labels.account_type.#{account_type}", default: account_type.to_s)
    end

    def profile_wall_props(user)
      {
        enabled: Community::ProfileWallPolicy.enabled?,
        can_post: logged_in? && Community::ProfileWallPolicy.can_post?(author: current_user, profile_user: user),
        post_url: forum_user_profile_posts_path(user.username)
      }
    end

    def serialize_profile_posts(user)
      return [] unless Community::ProfileWallPolicy.enabled?

      Community::ProfilePost.where(profile_user: user).published.recent
        .includes(:author, comments: :author).limit(20).map do |post|
        {
          id: post.id,
          body: post.body,
          author: profile_actor(post.author),
          created_at: l(post.created_at, format: :short),
          can_delete: can_manage_profile_post?(post.user_id, user.id),
          delete_url: forum_profile_post_path(post.id),
          comment_url: forum_profile_post_comments_path(post.id),
          comments: post.comments.to_a.select(&:published?).sort_by(&:created_at).map do |comment|
            {
              id: comment.id,
              body: comment.body,
              author: profile_actor(comment.author),
              created_at: l(comment.created_at, format: :short),
              can_delete: can_manage_profile_post?(comment.user_id, user.id),
              delete_url: forum_profile_post_comment_path(comment.id)
            }
          end
        }
      end
    end

    def profile_actor(actor)
      {
        username: actor.username,
        display_name: actor.display_name,
        avatar_url: actor.avatar_url,
        url: forum_user_path(actor.username)
      }
    end

    def can_manage_profile_post?(author_id, wall_owner_id)
      return false unless logged_in?

      author_id == current_user.id ||
        wall_owner_id == current_user.id ||
        current_user.permission?("forum.topics.lock") ||
        current_user.permission?("admin.access")
    end

    def serialize_game_permission_groups(user)
      profile = user.minecraft_player_profiles.first
      return [] unless profile

      profile.permission_groups.order(weight: :desc).map do |group|
        { key: group.group_key, label: group.group_label.presence || group.group_key, source: group.source }
      end
    end

    def serialize_minecraft_profile(user)
      profile = user.minecraft_player_profiles.first
      unless profile
        legacy = user.minecraft_identities.order(linked_at: :desc).first
        profile = legacy&.player_profile
      end

      unless profile
        return {
          linked: false,
          link_url: (logged_in? && current_user.id == user.id) ? minecraft_link_path : nil
        }
      end

      identity = profile.active_identity
      legacy = user.minecraft_identities.find_by(player_profile: profile) || user.minecraft_identities.order(linked_at: :desc).first

      fields = profile.profile_field_values.map do |value|
        definition = Minecraft::ProfileFieldDefinition.find_by(key: value.field_key)
        next unless definition&.active?

        { key: value.field_key, label: definition.label, value: value.value, field_type: definition.field_type, group: definition.group_name }
      end.compact

      {
        linked: true,
        player_id: profile.public_id,
        username: identity&.username || legacy&.username,
        uuid: identity&.external_uuid || legacy&.uuid,
        identity_type: identity&.identity_type || legacy&.identity_type || "java",
        skin_texture_url: identity&.skin_texture_url || legacy&.skin_texture_url,
        skin_model: identity&.skin_model || legacy&.skin_model,
        last_seen_ingame_at: (identity&.last_seen_ingame_at || legacy&.last_seen_ingame_at)&.then { |t| l(t, format: :short) },
        fields: fields,
        link_url: (logged_in? && current_user.id == user.id) ? minecraft_link_path : nil
      }
    end
  end
end
