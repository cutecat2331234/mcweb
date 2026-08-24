# frozen_string_literal: true

module Community
  class UsersController < ApplicationController
    include Community::TopicListPreloadable
    include ViewerScopedNoStoreResponse

    before_action :require_login, only: %i[update]

    def card
      user = User.active.find_by!(username: params[:id])
      activity = user_profile_activity(user)
      trust = Community::TrustLevel.level_info(user)
      posts_count = listed_posts_by(user).count
      badges = user.user_badges.includes(:badge).order(granted_at: :desc).limit(3).map do |ub|
        {
          name: ub.badge.name,
          icon: ub.badge.icon,
          color: ub.badge.color,
          granted_at: l(ub.granted_at, format: :short)
        }
      end
      memberships = Commerce::SerializeUserMemberships.public_for_user(user, limit: 3)
      likes_received = listed_reactions_received_by(user).count
      following = logged_in? && current_user.id != user.id && Community::UserFollow.exists?(follower: current_user, followed: user)
      payload = {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        trust_level: trust[:level],
        trust_name: trust[:name],
        posts_count: posts_count,
        likes_received: likes_received,
        reaction_score: listed_reaction_score_for(user),
        trophy_points: Community::TrophyPoints.for_user(user),
        groups: serialize_user_groups(user),
        bio: user.bio.presence,
        member_since: l(user.created_at, format: :short),
        badges: badges,
        memberships: memberships,
        message_url: (logged_in? && current_user.id != user.id && Community::TrustLevel.can_send_pm?(current_user)) ? new_forum_conversation_path(to: user.username) : nil,
        follow_url: (logged_in? && current_user.id != user.id) ? forum_user_follow_path(user.username) : nil,
        following: following
      }

      payload.merge!(activity.card)

      render json: payload
    end

    def show
      user = User.find_by!(username: params[:id])
      activity = user_profile_activity(user)
      visibility = activity.visibility
      User.where(id: user.id).update_all("forum_profile_views = forum_profile_views + 1") if logged_in? && current_user.id != user.id
      tab = params[:tab].to_s.in?(%w[topics posts store assigned minecraft]) ? params[:tab] : "topics"
      topics_scope = Community::ForumAccess.listed_topic_scope(
        relation: Community::Topic.where(user: user),
        user: current_user
      ).order(created_at: :desc)
      posts_scope = listed_posts_by(user).includes(:topic).order(created_at: :desc)
      posts_count = posts_scope.count
      @pagy_topics, topics = pagy(:offset, preload_topics(topics_scope), limit: 20, page: [ params[:topics_page].to_i, 1 ].max)
      @pagy_posts, posts = pagy(:offset, posts_scope, limit: 20, page: [ params[:posts_page].to_i, 1 ].max)
      assigned_scope = Community::ForumAccess.topic_scope(
        relation: Community::Topic.published_listed,
        user: current_user
      ).where(assigned_to: user).order(last_posted_at: :desc)
      @pagy_assigned, assigned_topics = pagy(:offset, preload_topics(assigned_scope), limit: 20, page: [ params[:assigned_page].to_i, 1 ].max)
      trust = Community::TrustLevel.level_info(user)
      liked_rows = listed_posts_by(user)
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
      store_orders = if logged_in? && current_user.id == user.id
                       Commerce::Order.where(
                         user: user,
                         status: Community::UserProfileActivitySerializer::COMPLETED_ORDER_STATUSES
                       )
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
          resolved_title: resolved_user_title(user, posts_count: posts_count),
          forum_flair_color_hex: user.forum_flair_color_hex,
          avatar_url: user.avatar_url,
          bio: user.bio,
          trust_level: trust[:level],
          trust_name: trust[:name],
          likes_received: listed_reactions_received_by(user).count,
          reaction_score: listed_reaction_score_for(user),
          trophy_points: Community::TrophyPoints.for_user(user),
          groups: serialize_user_groups(user),
          member_since: l(user.created_at, format: :long),
          forum_signature: forum_signatures_enabled? ? user.forum_signature : nil,
          topics_count: topics_scope.count,
          posts_count: posts_count,
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
          warning_points: (logged_in? && (current_user.id == user.id || current_user.permission?("forum.users.warn") || current_user.permission?("admin.access"))) ? Community::UserWarning.total_points_for(user) : nil,
          store_credit_label: (logged_in? && current_user.id == user.id && user.store_credit_cents.to_i.positive?) ? format_money(user.store_credit_cents.to_i, "CNY") : nil,
          store_wallet_url: (logged_in? && current_user.id == user.id) ? store_wallet_path : nil
        }
          .merge(activity.profile)
          .merge(private_profile_details(user, visibility: visibility))
          .merge(profile_activity_preference(user, visibility: visibility)),
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
            tier: ub.badge.tier,
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
        account_type: visibility.account_type? ? account_type_label(user.account_type) : nil,
        role_names: visibility.role_assignments? ? user.roles.order(:name).pluck(:name) : [],
        game_permission_groups: visibility.game_permission_groups? ? serialize_game_permission_groups(user) : [],
        memberships: serialized_memberships(user, visibility: visibility),
        minecraft: serialize_minecraft_profile(user, activity: activity),
        skin_mode: SiteSetting.get("minecraft.profile.skin_mode", "2d"),
        profile_sections: SiteSetting.get("minecraft.profile.sections", "minecraft,trust,roles,game_groups").to_s.split(",").map(&:strip).reject(&:blank?),
        custom_fields: Community::SerializeUserFields.for(user: user, viewer: current_user),
        profile_wall: profile_wall_props(user),
        profile_posts: serialize_profile_posts(user)
      }, encrypt_history: true
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

      user_saved = false
      field_result = nil
      # Persist core profile attributes and custom field values atomically so a
      # field validation failure does not leave core attributes committed.
      Identity::UserMutationLock.with_users(users: [ user ]) do |locked_users|
        user = locked_users.fetch(user.id)
        user_saved = user.update(user_params)
        raise ActiveRecord::Rollback unless user_saved

        if params.key?(:user_fields)
          field_result = Community::SyncUserFieldValues.call(
            user: user,
            values: params[:user_fields].present? ? params[:user_fields].to_unsafe_h : {},
            context: :profile
          )
          raise ActiveRecord::Rollback unless field_result.success?
        end
      end

      if !user_saved
        redirect_to forum_user_path(user.username), alert: user.errors.full_messages.to_sentence
      elsif field_result && !field_result.success?
        redirect_to forum_user_path(user.username), alert: field_result.errors.values.join(" ")
      else
        redirect_to forum_user_path(user.username), notice: t("mcweb.flash.profile_updated")
      end
    end

    private

    def listed_posts
      @listed_posts ||= Community::ForumAccess.listed_post_scope(
        relation: Community::Post.all,
        user: current_user
      )
    end

    def listed_posts_by(user)
      listed_posts.where(user: user)
    end

    def listed_reactions_received_by(user)
      Community::Reaction.where(
        forum_post_id: listed_posts_by(user).select(:id)
      )
    end

    def listed_reaction_score_for(user)
      score_map = Community::Reaction.score_map
      listed_reactions_received_by(user).group(:emoji).count.sum do |emoji, count|
        count * score_map.fetch(emoji.to_s, 1)
      end
    end

    def user_params
      permitted = params.require(:user).permit(
        :bio,
        :forum_title,
        :forum_signature,
        :forum_flair_color_hex,
        :forum_pm_policy,
        :forum_profile_activity_public
      )
      permitted.delete(:forum_pm_policy) unless Community::PmPolicy::POLICIES.include?(permitted[:forum_pm_policy])
      enforce_signature_rules!(permitted)
      permitted
    end

    # XenForo-style signature policy: respect the admin enable flag, a minimum
    # trust level, and a max length (all from SiteSetting).
    def enforce_signature_rules!(permitted)
      return unless permitted.key?(:forum_signature)

      enabled = SiteSetting.get("forum.signatures_enabled", "true") != "false"
      min_trust = SiteSetting.get("forum.min_trust_level_signature", "0").to_i
      max_length = SiteSetting.get("forum.signature_max_length", "1000").to_i

      trust_allowed =
        Mcweb::DeveloperMode.allow?(:skip_anti_spam) ||
        Community::TrustLevel.level_for(current_user) >= min_trust
      unless enabled && trust_allowed
        permitted.delete(:forum_signature)
        return
      end

      permitted[:forum_signature] = permitted[:forum_signature].to_s.first(max_length) if max_length.positive?
    end

    def attach_forum_avatar!(user, file:)
      return t("mcweb.services.errors.avatar_file_required") unless file.respond_to?(:read)

      inspected = Community::ImageUploadInspector.call(io: file, max_bytes: 2.megabytes)
      return t("mcweb.services.errors.avatar_too_large") if inspected.too_large?
      return t("mcweb.services.errors.avatar_unsupported_format") unless inspected.success?

      user.forum_avatar.attach(
        io: StringIO.new(inspected.payload),
        filename: "avatar.#{inspected.extension}",
        content_type: inspected.content_type,
        identify: false
      )
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

    def private_profile_details(user, visibility:)
      return {} unless visibility.private_activity?

      {
        profile_views: user.forum_profile_views,
        trust_progress: Community::TrustLevel.progress_for(user),
        **(visibility.owner? ? { forum_pm_policy: user.forum_pm_policy } : {})
      }
    end

    def profile_activity_preference(user, visibility:)
      return {} unless visibility.owner?

      { forum_profile_activity_public: user.forum_profile_activity_public? }
    end

    def serialized_memberships(user, visibility:, limit: nil)
      return Commerce::SerializeUserMemberships.for_user(user, limit: limit) if visibility.private_activity?

      Commerce::SerializeUserMemberships.public_for_user(user, limit: limit)
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
          edited: post.edited?,
          revision: post.revision,
          can_edit: logged_in? && current_user.id == post.user_id,
          edit_url: (logged_in? && current_user.id == post.user_id) ? forum_profile_post_path(post.id) : nil,
          can_delete: can_manage_profile_post?(post.user_id, user.id),
          delete_url: forum_profile_post_path(post.id),
          report_url: (logged_in? && current_user.id != post.user_id) ? new_forum_report_path(reportable_type: "Community::ProfilePost", reportable_id: post.id) : nil,
          comment_url: forum_profile_post_comments_path(post.id),
          comments: post.comments.to_a.select(&:published?).sort_by(&:created_at).map do |comment|
            {
              id: comment.id,
              body: comment.body,
              author: profile_actor(comment.author),
              created_at: l(comment.created_at, format: :short),
              edited: comment.edited?,
              revision: comment.revision,
              can_edit: logged_in? && current_user.id == comment.user_id,
              edit_url: (logged_in? && current_user.id == comment.user_id) ? forum_profile_post_comment_path(comment.id) : nil,
              can_delete: can_manage_profile_post?(comment.user_id, user.id),
              delete_url: forum_profile_post_comment_path(comment.id),
              report_url: (logged_in? && current_user.id != comment.user_id) ? new_forum_report_path(reportable_type: "Community::ProfilePostComment", reportable_id: comment.id) : nil
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
      profile = primary_minecraft_account(user)&.fetch(:profile)
      return [] unless profile

      profile.permission_groups.order(weight: :desc).map do |group|
        { key: group.group_key, label: group.group_label.presence || group.group_key, source: group.source }
      end
    end

    def serialize_minecraft_profile(user, activity:)
      account = primary_minecraft_account(user)
      unless account
        return {
          linked: false,
          link_url: (logged_in? && current_user.id == user.id) ? minecraft_link_path : nil
        }
      end

      profile = account.fetch(:profile)
      identity = account.fetch(:identity)

      fields = profile.profile_field_values.map do |value|
        definition = Minecraft::ProfileFieldDefinition.find_by(key: value.field_key)
        next unless definition&.active?
        next unless minecraft_profile_field_visible?(definition, user: user)

        { key: value.field_key, label: definition.label, value: value.value, field_type: definition.field_type, group: definition.group_name }
      end.compact

      {
        linked: true,
        player_id: profile.public_id,
        username: identity.username,
        uuid: minecraft_identity_details_visible?(user) ? identity.external_uuid : nil,
        identity_type: identity.identity_type,
        primary_account: true,
        skin_cached: identity.skin_cached?,
        skin_avatar_url: cached_skin_path(identity, :skin_avatar_file, "avatar") || "/minecraft/default-skin-avatar.png",
        skin_full_url: cached_skin_path(identity, :skin_full_file, "full"),
        skin_texture_url: cached_skin_path(identity, :skin_texture_file, "skin"),
        skin_model: identity.skin_model,
        fields: fields,
        link_url: (logged_in? && current_user.id == user.id) ? minecraft_link_path : nil
      }.merge(activity.minecraft(identity: identity))
    end

    def user_profile_activity(user)
      serializer = Community::UserProfileActivitySerializer.new(user: user, viewer: current_user)
      mark_viewer_scoped_no_store_response! if serializer.visible?
      serializer
    end

    def minecraft_profile_field_visible?(definition, user:)
      case definition.visibility
      when "public"
        true
      when "owner"
        logged_in? && (current_user.id == user.id || current_user.permission?("minecraft.players.view"))
      when "staff"
        logged_in? && current_user.permission?("minecraft.players.view")
      else
        false
      end
    end

    def minecraft_identity_details_visible?(user)
      logged_in? && (current_user.id == user.id || current_user.permission?("minecraft.players.view"))
    end

    def primary_minecraft_account(user)
      @primary_minecraft_accounts ||= {}
      return @primary_minecraft_accounts[user.id] if @primary_minecraft_accounts.key?(user.id)

      link = Minecraft::IdentityLink.active
                                      .primary
                                      .where(user_id: user.id)
                                      .includes(player_profile: { player_identities: [
                                        :skin_texture_file_attachment,
                                        :skin_avatar_file_attachment,
                                        :skin_full_file_attachment
                                      ] })
                                      .first
      identity = link&.player_profile&.active_identity
      @primary_minecraft_accounts[user.id] = if link && identity
                                                { link: link, profile: link.player_profile, identity: identity }
      end
    end

    def cached_skin_path(identity, attachment_name, variant)
      attachment = identity.public_send(attachment_name)
      return unless attachment.attached?

      minecraft_cached_skin_path(identity, variant: variant)
    end
  end
end
