Rails.application.routes.draw do
  root 'dashboard#index'
  
  # Strava OAuth
  get '/auth/strava', as: 'strava_login'
  get '/auth/strava/callback', to: 'sessions#create'
  
  # Main app routes
  get 'dashboard', to: 'dashboard#index'
  get 'activities', to: 'activities#index'
  get 'activities/:id', to: 'activities#show', as: 'activity'
  post 'activities/import', to: 'activities#import', as: 'activities_import'
  post 'activities/import/:id', to: 'activities#import_speed', as: 'activities_import_speed_data'
  get "records", to: 'records#index'
  get 'insights', to: 'insights#index'
end