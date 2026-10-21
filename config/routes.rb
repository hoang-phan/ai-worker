require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Sidekiq::Web => "/sidekiq"

  resources :projects do
    post :sync_slack, on: :member
    post :brainstorm, on: :member
    resources :jira_syncs, except: %i[index show] do
      post :run, on: :member
    end
    resources :bugsnag_syncs, except: %i[index show] do
      post :run, on: :member
    end
    resources :workflows, except: :index do
      member do
        post :start
        post :run_stage
        post :clone
        post :move
        post :advance
        post :resume
        post :rollback_to_review
        delete "images/:name", action: :destroy_image, as: :image, constraints: { name: /[^\/]+/ }
      end
      resources :stages, only: %i[new create edit update destroy]
    end
  end

  resources :prompt_templates
  resource :settings, only: %i[show update]

  root "projects#index"
end
