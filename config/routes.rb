Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :projects do
    resources :workflows, except: :index
  end

  resources :prompt_templates

  root "projects#index"
end
