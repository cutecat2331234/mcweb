Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "website/home#index"

  namespace :setup, path: "setup" do
    root "wizard#index"
    get "complete", to: "wizard#complete", as: :complete
    get ":step", to: "wizard#show", as: :step
    patch ":step", to: "wizard#update"
  end

  namespace :identity do
    get "sign-in", to: "sessions#new", as: :sign_in
    resource :session, only: %i[create destroy]
    resources :registrations, only: %i[new create], path: "register"
    resources :password_resets, only: %i[new create edit update], param: :token
    resource :email_verification, only: %i[show], path: "verify-email"
    resources :sessions_management, only: %i[index destroy], path: "sessions"
  end

  namespace :admin do
    root "dashboard#index"
    resources :users, only: %i[index show]
    resources :roles, only: %i[index]
    resources :audit_logs, only: %i[index]
    namespace :forum do
      resources :sections, only: %i[index]
      resources :topics, only: %i[index]
      resources :reports, only: %i[index]
    end
    namespace :store do
      resources :products, only: %i[index]
      resources :orders, only: %i[index]
      resources :fulfillments, only: %i[index]
    end
    namespace :website do
      resources :pages, only: %i[index]
      resources :articles, only: %i[index]
    end
    namespace :minecraft do
      resources :servers, only: %i[index]
    end
    namespace :system do
      resource :settings, only: %i[show update]
      resources :jobs, only: %i[index]
    end
  end

  scope module: :community, path: "forum", as: :forum do
    resources :sections, only: %i[index show]
    resources :topics, only: %i[index show new create]
    resources :posts, only: %i[create]
    resources :reports, only: %i[new create]
    get "search", to: "search#index"
  end

  scope module: :commerce, path: "store", as: :store do
    resources :products, only: %i[index show]
    resource :cart, only: %i[show update]
    resources :orders, only: %i[index show]
    resource :checkout, only: %i[show create]
    post "webhooks/:provider", to: "webhooks#create", as: :webhook
  end

  scope module: :website, as: :website do
    resources :articles, only: %i[index show], path: "blog"
    get "pages/:slug", to: "pages#show", as: :page
  end

  get "health/live", to: "health#live"
  get "health/ready", to: "health#ready"

  namespace :minecraft do
    resource :link, only: %i[show create], controller: "link"
    namespace :connector do
      scope ":server_id" do
        post "heartbeat", to: "api#heartbeat"
        get "tasks", to: "api#tasks"
        post "tasks/:id/complete", to: "api#complete"
      end
    end
  end
end
