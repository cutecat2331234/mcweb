# frozen_string_literal: true

module Community
  # Discourse-style "New" list: recently created topics the current user has
  # never opened (no read state), within a configurable window. Topics the user
  # authored already carry a read state (CreateTopic marks floor 1 read), so they
  # are naturally excluded.
  class NewController < ApplicationController
    include Community::TopicFilterable
    include Community::TopicListPreloadable

    before_action :require_login

    def index
      filter = params[:filter].to_s.presence
      scope = preload_topics(filtered_new_topics(filter)).order(created_at: :desc, id: :desc)

      @pagy, topics = pagy(:offset, scope, limit: 30)

      render inertia: "Community/New/Index", props: {
        topics: serialize_topics(topics, read_states: {}),
        pagination: pagy_props(@pagy),
        filter: filter.to_s,
        filterOptions: topic_filter_options,
        activeFilters: Community::TopicListActiveFilters.call(filter: filter),
        windowDays: Community::Topic.new_topic_window_days,
        dismissUrl: forum_dismiss_new_feed_path,
        canDismiss: topics.any?,
        canBulkModerate: current_user.permission?("forum.topics.lock"),
        bulkModerateUrl: current_user.permission?("forum.topics.lock") ? bulk_moderate_forum_topics_path : nil
      }
    end

    def dismiss
      filter = params[:filter].to_s.presence
      public_ids = filtered_new_topics(filter).pluck(:public_id)
      Community::MarkTopicsRead.call(user: current_user, topic_public_ids: public_ids)
      redirect_to forum_new_feed_path(filter: filter), notice: t("mcweb.flash.new_dismissed")
    end

    private

    # New topics narrowed by the active list filter and blocked-author hiding,
    # shared by both the rendered list and "dismiss" so they stay in sync.
    def filtered_new_topics(filter)
      scope = filter_blocked_topics(Community::Topic.unseen_for(current_user))
      apply_topic_filter(scope, filter: filter, user: current_user)
    end
  end
end
