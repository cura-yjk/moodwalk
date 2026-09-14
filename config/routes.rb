Rails.application.routes.draw do
  devise_for :users

  root to: "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "calendar", to: "calendar#index"

  resource :location, only: [:update] do
    get :autocomplete, on: :collection
  end

  resources :journeys, only: [:create] do
    resources :walks, only: [:new, :create]
    member do
      patch :save
      get :highlights
    end
  end

  resources :walks, only: [:show, :edit, :update, :index] do
    member do
      patch :complete
      patch :attach_photo
      patch :share
      post :track
      post :share_quote
      get :memory
    end
  end

  resources :community_routes, only: [:index, :show]

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
