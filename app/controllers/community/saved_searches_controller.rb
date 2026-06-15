# frozen_string_literal: true

module Community
  class SavedSearchesController < ApplicationController
    before_action :require_login

    def index
      searches = current_user.forum_saved_searches.recent.limit(20)
      render json: searches.map { |search| serialize_saved_search(search) }
    end

    def create
      search = current_user.forum_saved_searches.build(saved_search_params)
      if search.save
        render json: serialize_saved_search(search), status: :created
      else
        render json: { error: search.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    def update
      search = current_user.forum_saved_searches.find(params[:id])
      if search.update(saved_search_update_params)
        render json: serialize_saved_search(search)
      else
        render json: { error: search.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    def destroy
      search = current_user.forum_saved_searches.find(params[:id])
      search.destroy!
      head :no_content
    end

    private

    def saved_search_params
      params.require(:saved_search).permit(:name, :query, :notify_daily, filters: {})
    end

    def saved_search_update_params
      params.require(:saved_search).permit(:notify_daily, :name)
    end

    def serialize_saved_search(search)
      {
        id: search.id,
        name: search.name,
        query: search.query,
        filters: search.filters,
        notify_daily: search.notify_daily?,
        url: forum_search_path(search_url_params(search)),
        update_url: forum_saved_search_path(search),
        delete_url: forum_saved_search_path(search)
      }
    end

    def search_url_params(search)
      filters = search.filters.symbolize_keys
      {
        q: search.query.presence,
        section: filters[:section].presence,
        category: filters[:category].presence,
        author: filters[:author].presence,
        tag: filters[:tag].presence,
        solved: filters[:solved].presence,
        locked: filters[:locked].presence,
        pinned: filters[:pinned].presence,
        wiki: filters[:wiki].presence,
        featured: filters[:featured].presence,
        announcement: filters[:announcement].presence,
        assigned: filters[:assigned].presence,
        assignee: filters[:assignee].presence,
        unlisted: filters[:unlisted].presence,
        archived: filters[:archived].presence,
        mine: filters[:mine].presence,
        scope: filters[:scope].presence,
        poll: filters[:poll].presence,
        noreplies: filters[:noreplies].presence,
        images: filters[:images].presence,
        created_after: filters[:created_after].presence,
        created_before: filters[:created_before].presence,
        topic_sort: filters[:topic_sort].presence,
        post_sort: filters[:post_sort].presence
      }.compact
    end
  end
end
