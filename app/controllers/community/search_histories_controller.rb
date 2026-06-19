# frozen_string_literal: true

module Community
  class SearchHistoriesController < ApplicationController
    before_action :require_login

    def destroy
      history = current_user.forum_search_histories.find(params[:id])
      history.destroy!
      redirect_to forum_search_path, notice: t("mcweb.flash.search_history_deleted")
    end

    def clear
      current_user.forum_search_histories.delete_all
      redirect_to forum_search_path, notice: t("mcweb.flash.search_history_cleared")
    end
  end
end
