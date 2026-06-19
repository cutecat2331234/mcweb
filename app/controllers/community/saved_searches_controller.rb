# frozen_string_literal: true

module Community
  class SavedSearchesController < ApplicationController
    before_action :require_login, except: :unsubscribe

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

    def unsubscribe
      search_id = Community::SavedSearchUnsubscribeToken.verify(params[:token])
      search = Community::SavedSearch.find(search_id)
      search.update!(notify_daily: false)
      redirect_to forum_preferences_path, notice: t("mcweb.flash.saved_search_notify_disabled", name: search.name)
    rescue Community::SavedSearchUnsubscribeToken::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to forum_search_path, alert: t("mcweb.flash.saved_search_unsubscribe_invalid")
    end

    private

    def saved_search_params
      params.require(:saved_search).permit(:name, :query, :notify_daily, :notify_in_app, :webhook_url, filters: {})
    end

    def saved_search_update_params
      params.require(:saved_search).permit(:notify_daily, :notify_in_app, :name, :webhook_url)
    end

    def serialize_saved_search(search)
      {
        id: search.id,
        name: search.name,
        query: search.query,
        filters: search.filters,
        notify_daily: search.notify_daily?,
        notify_in_app: search.notify_in_app?,
        filter_labels: Community::SavedSearchFilterSummary.call(search),
        url: forum_search_path(Community::SavedSearchPresenter.url_params(search)),
        rss_url: Community::SavedSearchPresenter.rss_path(search),
        webhook_url: search.webhook_url,
        update_url: forum_saved_search_path(search),
        delete_url: forum_saved_search_path(search)
      }
    end

    def search_url_params(search)
      Community::SavedSearchPresenter.url_params(search)
    end
  end
end
