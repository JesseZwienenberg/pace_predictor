class SessionsController < ApplicationController
    def create
        auth_hash = request.env['omniauth.auth']

        session[:strava_access_token] = auth_hash.credentials.token
        session[:strava_athlete_id] = auth_hash.uid
    
        redirect_to root_path, notice: 'Successfully connected to Strava!'
    end
end