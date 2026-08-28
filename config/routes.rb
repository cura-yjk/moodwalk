Rails.application.routes.draw do
  # Sets up all the standard authentication routes (sign in, sign out, sign up,
  # password reset, etc.) for the User model, provided by the Devise gem.
  devise_for :users

  # The homepage ("/") is handled by the "home" action in PagesController.
  root to: "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # "/calendar" shows the user's calendar view (e.g. a history of past walks by date).
  get "calendar", to: "calendar#index"

  # A "singular" resource, meaning there's only ever one "location" per current
  # user (no id in the URL). This just generates a route for updating it, e.g.
  # PATCH /location, used to save the user's current location.
  resource :location, only: [:update]

  # Journeys are pre-made walking routes. `only: []` means journeys themselves
  # don't get any routes of their own (no index/show/create/etc for journeys directly).
  # Instead, they're only used as a "parent" so we can nest walk routes under them.
  resources :journeys, only: [  ] do
    # Nested under a specific journey, so the URLs look like:
    #   GET  /journeys/:journey_id/walks/new    -> show a form to start a new walk
    #   POST /journeys/:journey_id/walks        -> actually create that walk
    # This is how a user "starts" a walk based on a chosen journey.
    resources :walks, only: [ :new, :create ]
  end

  # Walks, once created, are managed on their own (no journey_id needed in the URL).
  resources :walks, only: [ :show, :edit, :update, :index ] do
    # "member" routes act on one specific walk (they include the walk's :id).
    member do
      # PATCH /walks/:id/complete
      # Marks a walk as finished (likely sets completed_at, and maybe records
      # mood_after / reflection at the same time).
      patch :complete

      # PATCH /walks/:id/attach_photo
      # Lets the user attach a photo to a walk (e.g. after finishing it).
      patch :attach_photo
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
