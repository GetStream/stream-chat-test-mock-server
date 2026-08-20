require 'eventmachine'
require 'faye/websocket'
require 'puma'
require 'json'
require 'time'
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
require_relative 'helpers/reads'
require_relative 'helpers/moderation'
require_relative 'helpers/polls'
require_relative 'helpers/reminders'
require_relative 'helpers/threads'
require_relative 'robots/chat'
require_relative 'robots/participant'

$ws = nil
$message_list = []
$sync_events = []
$reminders = []
$polls = []
$user_mutes = []
$channel_mutes = []
$blocked_users = []
$block_hidden_channels = {}
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

# The health check is rebuilt on every send so its `me` carries the live
# moderation state. The static payload would reset the own user, wiping any
# mute or block a few seconds after the endpoint applied it. Token-error
# payloads set by jwt.rb pass through untouched.
def send_health_check
  payload = JSON.parse($health_check)
  payload['me'] = payload['me'].merge(live_own_user_state) if payload['type'] == 'health.check' && payload['me']
  $ws&.send(payload.to_s)
  $ws&.close(1000) if payload['type'] == 'connection.error'
end

Thread.new do
  loop do
    sleep 3
    send_health_check
  end
end
