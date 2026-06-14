# frozen_string_literal: true

module Website
  class PagesController < ApplicationController
    def show
      @page = Website::Page.published.find_by!(slug: params[:slug])
    end
  end
end
