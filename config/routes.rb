require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Sidekiq::Web => "/sidekiq"

  resources :projects do
    resources :jira_syncs, except: %i[index show] do
      post :run, on: :member
    end
    resources :workflows, except: :index do
      member do
        post :start
        post :resume
        post :rollback_to_review
        delete "images/:name", action: :destroy_image, as: :image, constraints: { name: /[^\/]+/ }
      end
      resources :stages, only: %i[edit update]
    end
  end

  resources :prompt_templates

  root "projects#index"
end
