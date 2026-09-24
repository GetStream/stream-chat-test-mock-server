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
# The websocket protocol the connected client negotiated. v1 authenticates through the
# connect URL and takes a health.check carrying `me` as its first frame; v2 authenticates
# with a text frame after the upgrade and takes a connection.ok instead.
$ws_protocol = :v1
$ws_authenticated = false
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

# Faye sockets must only be written from the EventMachine reactor thread. Frames sent from the
# health-check loop or a Puma request thread are otherwise silently dropped once the loop has
# closed a socket, so every send and close is handed to the reactor. The socket is captured at
# call time so a queued frame never lands on a socket opened after it was sent.
def ws_send(data)
  ws = $ws
  EM.schedule { ws.send(data) } if ws
end

def ws_close(code)
  ws = $ws
  EM.schedule { ws.close(code) } if ws
end

# The connection payload is rebuilt on every send so its `me` carries the live
# moderation state. The static payload would reset the own user, wiping any
# mute or block a few seconds after the endpoint applied it. Token-error
# payloads set by jwt.rb pass through untouched and close the socket on both protocols.
def connection_payload
  payload = JSON.parse($health_check)
  payload['me'] = payload['me'].merge(live_own_user_state) if payload['type'] == 'health.check' && payload['me']
  payload
end

def send_connection_error?(payload)
  return false unless payload['type'] == 'connection.error'

  ws_send(payload.to_s)
  ws_close(1000)
  true
end

# v2 handshake response: a single connection.ok carrying the own user.
def send_connection_ok
  payload = connection_payload
  return if send_connection_error?(payload)

  ws_send(
    {
      'type' => 'connection.ok',
      'created_at' => unique_date,
      'connection_id' => payload['connection_id'],
      'me' => payload['me']
    }.to_s
  )
end

def send_health_check
  payload = connection_payload
  return if send_connection_error?(payload)

  if $ws_protocol == :v2
    # v2 keeps the keepalive minimal: `me` rides on connection.ok instead.
    return unless $ws_authenticated

    ws_send(
      {
        'type' => 'health.check',
        'connection_id' => payload['connection_id'],
        'created_at' => unique_date,
        'custom' => {}
      }.to_s
    )
  else
    ws_send(payload.to_s)
  end
end

Thread.new do
  loop do
    sleep 3
    send_health_check
  end
end
