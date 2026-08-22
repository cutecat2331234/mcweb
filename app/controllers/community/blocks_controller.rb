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

    def update
      set_block(desired_state: true)
    end

    def destroy
      set_block(desired_state: false)
    end

    private

    def set_block(desired_state:)
      result = Community::SetUserBlock.call(
        blocker: current_user,
        blocked_username: params[:username],
        desired_state: desired_state
      )

      if result.success?
        redirect_back(
          fallback_location: forum_blocks_path,
          notice: result.value[:blocked] ? t("mcweb.flash.user_blocked") : t("mcweb.flash.user_unblocked"),
          status: :see_other
        )
      else
        redirect_back fallback_location: forum_blocks_path, alert: service_error_message(result), status: :see_other
      end
    end
  end
end
