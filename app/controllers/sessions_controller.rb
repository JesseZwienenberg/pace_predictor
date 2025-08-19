class SessionsController < ApplicationController
  def create
    auth = request.env['omniauth.auth']
    session[:strava_access_token] = auth.credentials.token
    redirect_to root_path
  end

  def omniauth_failure
    # This handles failures from the OmniAuth middleware
    redirect_to manual_token_path
  end

  def manual_token
    # Shows the form to manually enter token
  end

  def set_manual_token
    if params[:token].present?
      session[:strava_access_token] = params[:token]
      redirect_to root_path, notice: 'Strava token set successfully!'
    else
      redirect_to manual_token_path, alert: 'Please enter a valid token'
    end
  end
end