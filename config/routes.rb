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
    resources :users, only: %i[index show] do
      member do
        post :ban
        post :unban
      end
    end
    resources :roles, only: %i[index show]
    resources :audit_logs, only: %i[index show]
    namespace :forum do
      resources :categories
      resources :sections, only: %i[index show new create edit update]
      resources :topics, only: %i[index show]
      resources :reports, only: %i[index show update]
      resources :mutes, only: %i[create destroy]
      resources :censored_words, only: %i[index create destroy]
      resources :badges, only: %i[index new create edit update destroy]
      resources :tags
    end
    namespace :store do
      resources :categories
      resources :products
      resources :coupons
      resources :orders, only: %i[index show update] do
        collection do
          get :export
        end
      end
      resources :reviews, only: %i[index show update]
      resources :fulfillments, only: %i[index show update]
      resources :product_questions, only: %i[index destroy] do
        member do
          patch :hide
          patch :unhide
        end
      end
      post :uploads, to: "uploads#create"
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
      resources :ip_bans, only: %i[index create destroy]
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
    post "users/:username/follow", to: "follows#create", as: :user_follow
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
        post :merge
        post :mark_solved
        post :unsolve
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
        get :visit
      end
      collection do
        patch :mark_all_read
      end
    end
    get "search", to: "search#index"
    get "mentions/search", to: "mentions#search", as: :mention_search
    get "latest", to: "latest#index"
    get "activity", to: "activity#index"
    get "following", to: "follows#index"
    get "unread", to: "unread#index"
    patch "unread/mark_all_read", to: "unread#mark_all_read", as: :unread_mark_all_read
    post "preview", to: "previews#create"
    post "uploads", to: "uploads#create"
    get "bookmarks", to: "bookmarks#index"
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
    get "watching", to: "watched#index"
    get "watching/tags", to: "watched#tags", as: :watched_tags
    get "tags", to: "tags#index", as: :tags
    get "tags/:slug.rss", to: "rss#tag", as: :tag_rss, defaults: { format: :rss }
    get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }
    get "tags/:slug", to: "tags#show", as: :tag
    post "tags/:slug/subscription", to: "tags#toggle_subscription", as: :tag_subscription
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
        post :stock_alert, to: "stock_alerts#create"
        resources :reviews, only: %i[create], controller: "reviews" do
          member do
            post :helpful, action: :toggle_helpful
          end
        end
        resources :questions, only: %i[create], controller: "product_questions"
        post "questions/:question_id/answer", to: "product_questions#answer", as: :answer_question
      end
    end
    get "wishlist", to: "wishlist#index"
    post "wishlist/add_all_to_cart", to: "wishlist#add_all_to_cart", as: :add_all_to_cart_wishlist
    get "wishlist/share", to: "wishlist#share"
    get "wishlist/:token", to: "wishlist#public_show", as: :public_wishlist
    resource :cart, only: %i[show update] do
      post :preview_coupon, on: :member
    end
    resources :orders, only: %i[index show create] do
      member do
        post :cancel
        post :refund
        get :receipt
        get :receipt_pdf
        post :reorder
      end
    end
    resource :checkout, only: %i[show create], controller: "checkout" do
      post :preview_coupon, on: :member
    end
    post "webhooks/:provider", to: "webhooks#create", as: :webhook
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
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
