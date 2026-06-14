# frozen_string_literal: true

module Community
  class BlocksController < ApplicationController
    before_action :require_login

    def index
      blocks = Community::UserBlock
        .where(blocker: current_user)
        .includes(:blocked)
        .order(created_at: :desc)

      render inertia: "Community/Blocks/Index", props: {
        users: blocks.map do |block|
          user = block.blocked
          {
            username: user.username,
            display_name: user.display_name,
            profile_url: forum_user_path(user.username),
            blocked_at: l(block.created_at, format: :short),
            unblock_url: forum_block_user_path(user.username)
          }
        end
      }
    end

    def create
      result = Community::ToggleUserBlock.call(
        blocker: current_user,
        blocked_username: params[:username]
      )

      if result.success?
        redirect_back fallback_location: forum_blocks_path, notice: result.value[:blocked] ? "已拉黑该用户。" : "已取消拉黑。"
      else
        redirect_back fallback_location: forum_blocks_path, alert: service_error_message(result)
      end
    end
  end
end
