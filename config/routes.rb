require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Sidekiq::Web => "/sidekiq"

  resources :projects do
    post :sync_slack, on: :member, to: "project_slack_syncs#create"
    post :brainstorm, on: :member, to: "project_brainstorms#create"
    resources :jira_syncs, except: %i[index show] do
      post :run, on: :member
    end
    resources :bugsnag_syncs, except: %i[index show] do
      post :run, on: :member
    end
    resources :agents, except: %i[index show]
    resources :workflows, except: :index do
      post :log_time, on: :collection, to: "workflow_time_logs#create"
      member do
        post :start, to: "workflow_transitions#start"
        post :resume, to: "workflow_transitions#resume"
        post :rollback_to_review, to: "workflow_transitions#rollback_to_review"
        post :run_stage, to: "workflow_runbooks#run_stage"
        post :advance, to: "workflow_runbooks#advance"
        post :clone, to: "workflow_runbooks#clone"
        post :move, to: "workflow_positions#move"
        delete "images/:name", to: "workflow_images#destroy_image", as: :image, constraints: { name: /[^\/]+/ }
      end
      resources :stages, only: %i[new create edit update destroy]
    end
  end

  resources :prompt_templates
  resource :settings, only: %i[show update]

  root "projects#index"
end
