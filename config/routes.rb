Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  get "calendar", to: "calendars#show", as: :calendar
  resources :leave_requests, only: %i[index new create destroy]
  resources :notifications, only: %i[index update] do
    collection { patch :mark_all_read }
  end

  namespace :manager do
    resource :calendar, only: :show
    resources :leave_requests, only: :index do
      member do
        patch :approve
        patch :reject
      end
    end
  end

  namespace :admin do
    resources :calendar_reviews, only: %i[index update]
    resources :federal_calendars, except: %i[show destroy] do
      collection { post :import }
    end
    resources :leave_types, except: %i[show destroy]
    resources :users, except: %i[show destroy]
  end

  root "home#show"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
