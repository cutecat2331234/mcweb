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

    def destroy
      search = current_user.forum_saved_searches.find(params[:id])
      search.destroy!
      head :no_content
    end

    private

    def saved_search_params
      params.require(:saved_search).permit(:name, :query, filters: {})
    end

    def serialize_saved_search(search)
      {
        id: search.id,
        name: search.name,
        query: search.query,
        filters: search.filters,
        url: forum_search_path(search_url_params(search)),
        delete_url: forum_saved_search_path(search)
      }
    end

    def search_url_params(search)
      filters = search.filters.symbolize_keys
      {
        q: search.query.presence,
        section: filters[:section].presence,
        author: filters[:author].presence,
        tag: filters[:tag].presence,
        solved: filters[:solved].presence,
        locked: filters[:locked].presence,
        pinned: filters[:pinned].presence,
        wiki: filters[:wiki].presence,
        featured: filters[:featured].presence,
        announcement: filters[:announcement].presence,
        created_after: filters[:created_after].presence,
        created_before: filters[:created_before].presence,
        topic_sort: filters[:topic_sort].presence,
        post_sort: filters[:post_sort].presence
      }.compact
    end
  end
end
