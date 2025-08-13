Rails.application.config.middleware.use OmniAuth::Builder do
  provider :strava, ENV['STRAVA_CLIENT_ID'], ENV['STRAVA_CLIENT_SECRET'], scope: 'read,activity:read_all'
end

OmniAuth.config.allowed_request_methods = [:get, :post]