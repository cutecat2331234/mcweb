# frozen_string_literal: true

module Admin
  module Website
    class HomeController < BaseController
      DESTINATIONS = [
        [ "website.pages.read", :admin_website_pages_path ],
        [ "website.articles.read", :admin_website_articles_path ],
        [ "website.content.restore", :admin_website_recycle_bin_path ],
        [ "website.content.purge", :admin_website_recycle_bin_path ],
        [ "website.templates.manage", :admin_frontend_templates_path ]
      ].freeze

      def show
        destination = DESTINATIONS.find do |permission, _helper|
          current_user.permission?(permission)
        end
        redirect_to(destination ? public_send(destination.last) : admin_root_path)
      end
    end
  end
end
