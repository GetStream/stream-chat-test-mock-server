require 'eventmachine'
require 'faye/websocket'
require 'puma'
require 'json'
require 'sinatra'
require 'securerandom'
require_relative 'server/endpoints'
require_relative 'server/extensions'
require_relative 'server/data'
require_relative 'server/mocks'
require_relative 'helpers/user'
require_relative 'helpers/event'
require_relative 'helpers/message'
require_relative 'helpers/reaction'
require_relative 'robots/chat'
require_relative 'robots/participant'

$ws = nil
$message_list = []
$channel_list = Mocks.channels
$current_channel_id = Mocks.event['channel_id']
$health_check = Mocks.health_check.to_s

set :port, ARGV[0] || 4568

before do
  content_type :json
  request.body.rewind
end

Thread.new do
  loop do
    sleep 3
    $ws&.send($health_check)
  end
end
