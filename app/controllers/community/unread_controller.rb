# frozen_string_literal: true

module Community
  class UnreadController < ApplicationController
    before_action :require_login

    def index
      read_states = Community::ReadState
        .with_unread_for(current_user)
        .includes(topic: :user)
        .limit(50)

      topics = read_states.map(&:topic).reject { |topic| blocked_user_ids.include?(topic.user_id) }
      states_by_topic = read_states.index_by(&:forum_topic_id)

      render inertia: "Community/Unread/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: states_by_topic[topic.id]) },
        markAllReadUrl: forum_unread_mark_all_read_path
      }
    end

    def mark_all_read
      result = Community::MarkAllTopicsRead.call(user: current_user)

      if result.success?
        redirect_to forum_unread_path, notice: "全部主题已标记为已读。"
      else
        redirect_to forum_unread_path, alert: service_error_message(result)
      end
    end
  end
end
