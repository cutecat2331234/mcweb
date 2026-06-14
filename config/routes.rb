Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount MissionControl::Jobs::Engine, at: "/jobs"

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
    resources :roles, only: %i[index show]
    resources :audit_logs, only: %i[index show]
    namespace :forum do
      resources :sections, only: %i[index show new create edit update]
      resources :topics, only: %i[index show]
      resources :reports, only: %i[index show update]
      resources :mutes, only: %i[create destroy]
    end
    namespace :store do
      resources :categories
      resources :products
      resources :coupons
      resources :orders, only: %i[index show update]
      resources :reviews, only: %i[index show update]
      resources :fulfillments, only: %i[index show update]
    end
    namespace :website do
      resources :pages, only: %i[index show]
      resources :articles, only: %i[index show]
    end
    namespace :minecraft do
      resources :servers, only: %i[index show]
    end
    namespace :system do
      resource :settings, only: %i[show update]
      resources :jobs, only: %i[index]
    end
  end

  scope module: :community, path: "forum", as: :forum do
    resources :sections, only: %i[index show] do
      member do
        post :subscription, action: :toggle_subscription
      end
    end
    resources :drafts, only: %i[index create update destroy], param: :id do
      member do
        get :edit
        post :publish
      end
    end
    post "users/:username/block", to: "blocks#create", as: :block_user
    resources :polls, only: [] do
      member do
        post :vote
      end
    end
    get "latest.rss", to: "rss#latest", as: :latest_rss, defaults: { format: :rss }
    get "sections/:id.rss", to: "rss#section", as: :section_rss, defaults: { format: :rss }
    resources :topics, only: %i[show new create update] do
      member do
        post :moderate
        post :move
        post :mark_solved
        patch :slow_mode, action: :update_slow_mode
        post :subscription, action: :toggle_subscription
        post :bookmark, action: :toggle_bookmark
      end
    end
    resources :posts, only: %i[create update destroy] do
      member do
        post :reaction, action: :toggle_reaction
        post :bookmark, action: :toggle_bookmark
        post :moderate
        get :edits
      end
    end
    resources :reports, only: %i[new create]
    resources :notifications, only: %i[index] do
      member do
        patch :mark_read
      end
      collection do
        patch :mark_all_read
      end
    end
    get "search", to: "search#index"
    get "latest", to: "latest#index"
    get "unread", to: "unread#index"
    patch "unread/mark_all_read", to: "unread#mark_all_read", as: :unread_mark_all_read
    post "preview", to: "previews#create"
    get "bookmarks", to: "bookmarks#index"
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
    get "watching", to: "watched#index"
    get "tags", to: "tags#index", as: :tags
    get "tags/:slug.rss", to: "rss#tag", as: :tag_rss, defaults: { format: :rss }
    get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }
    get "tags/:slug", to: "tags#show", as: :tag
    resources :conversations, only: %i[index show new create] do
      resources :messages, only: %i[create], controller: "conversation_messages"
    end
    resources :users, only: %i[show update], param: :id
  end

  get "payments/fake/:id", to: "payments/fake#show", as: :fake_payment
  post "payments/fake/:id", to: "payments/fake#create"

  scope module: :commerce, path: "store", as: :store do
    resources :products, only: %i[index show] do
      member do
        post :wishlist, to: "wishlist#toggle"
        resources :reviews, only: %i[create], controller: "reviews"
      end
    end
    get "wishlist", to: "wishlist#index"
    resource :cart, only: %i[show update]
    resources :orders, only: %i[index show create] do
      member do
        post :cancel
        post :refund
      end
    end
    resource :checkout, only: %i[show create], controller: "checkout" do
      post :preview_coupon, on: :member
    end
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
