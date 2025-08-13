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
end