require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Sidekiq::Web => "/sidekiq"

  resources :projects do
    resources :workflows, except: :index do
      member do
        post :start
      end
      resources :stages, only: %i[edit update]
    end
  end

  resources :prompt_templates

  root "projects#index"
end
