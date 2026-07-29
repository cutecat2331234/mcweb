# frozen_string_literal: true

module Admin
  class PluginPagesController < BaseController
    def show
      page = contribution_presenter.page(surface: "admin")
      return head :not_found unless page

      render inertia: "Admin/Plugins/Page", props: {
        title: page.fetch(:title),
        pluginPage: page
      }
    end

    private

    def contribution_presenter
      PluginContributionPresenter.new(
        user: current_user,
        locale: I18n.locale,
        path: request.path
      )
    end
  end
end
