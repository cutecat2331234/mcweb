# frozen_string_literal: true

module Community
  class SearchHistoriesController < ApplicationController
    before_action :require_login

    def destroy
      history = current_user.forum_search_histories.find(params[:id])
      history.destroy!
      redirect_to forum_search_path, notice: "已删除该条搜索历史。"
    end

    def clear
      current_user.forum_search_histories.delete_all
      redirect_to forum_search_path, notice: "搜索历史已清空。"
    end
  end
end
