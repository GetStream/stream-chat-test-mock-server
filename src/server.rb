require 'eventmachine'
require 'faye/websocket'
require 'puma'
require 'json'
require 'sinatra'
require 'securerandom'
require_relative 'server/config'
require_relative 'server/data'
require_relative 'server/endpoints'
require_relative 'server/extensions'
require_relative 'server/jwt'
require_relative 'server/mocks'
require_relative 'helpers/user'
require_relative 'helpers/events'
require_relative 'helpers/messages'
require_relative 'helpers/members'
require_relative 'helpers/reactions'
require_relative 'helpers/channels'
require_relative 'robots/chat'
require_relative 'robots/participant'

$ws = nil
$message_list = []
$channel_list = Mocks.channels
$current_channel_id = Mocks.event_ws['channel_id']
$health_check = Mocks.health_check.to_s
$fail_messages = nil
$freeze_messages = nil
$delay_messages = nil
$forbidden_words = ["wth"]
$all_channels_loaded = false

set :port, ARGV[0] || 4568

before do
  content_type :json
  request.body.rewind
end

get '/stop' do
  Thread.new do
    sleep 1
    exit
  end
end

def send_health_check
  $ws&.send($health_check)
  $ws&.close(1000) if JSON.parse($health_check)['type'] == 'connection.error'
end

Thread.new do
  loop do
    sleep 3
    send_health_check
  end
end
