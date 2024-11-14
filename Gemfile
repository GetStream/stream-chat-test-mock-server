source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

gem 'rubocop', '1.38', group: :rubocop_dependencies
gem 'sinatra', group: :sinatra_dependencies

group :rubocop_dependencies do
  gem 'rubocop-performance'
  gem 'rubocop-require_tools'
end

group :sinatra_dependencies do
  gem 'eventmachine'
  gem 'faye-websocket'
  gem 'puma'
  gem 'rackup'
end
