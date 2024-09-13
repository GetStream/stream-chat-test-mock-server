require 'eventmachine'
require 'faye/websocket'
require 'puma'
require 'json'
require 'sinatra'
require 'securerandom'
require_relative 'log'
require_relative 'extensions'
require_relative 'data'
require_relative 'participant'
require_relative 'mocks'
require_relative 'helpers/event'
require_relative 'helpers/message'

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

# Connect to WebSocket
get '/connect' do
  if Faye::WebSocket.websocket?(request.env)
    $ws = Faye::WebSocket.new(request.env)
    $ws.on(:open) { |_| $ws.send($health_check) }
    $ws.on(:close) { $ws = nil }
    $ws.rack_response
  end
end

# Synchronize
post '/sync' do
  { events: [] }.to_json
end

# Show channel list
get '/channels' do
  $channel_list['channels'][0]['messages'] = $message_list
  $channel_list.to_s
end

# Show channel info
post '/channels/:channel_type/:channel_id/query' do
  $channel_list['channels'][0].to_s
end

# Send event
post '/channels/messaging/:channel_id/event' do
  create_event(type: JSON.parse(request.body.read)['event']['type'], channel_id: params[:channel_id])
end

# Read message
post '/channels/messaging/:channel_id/read' do
  create_event(type: 'message.read', channel_id: params[:channel_id])
end

# Send message
post '/channels/messaging/:channel_id/message' do
  create_message(request_body: request.body.read, channel_id: params[:channel_id])
end

# Update message
post '/messages/:message_id' do
  # FIXME: NOW
end

# Send reaction
post '/messages/:message_id/reaction' do
  Mocks.reaction.to_s # FIXME
end

# Update reaction
post '/messages/:message_id/reaction/:reaction_type' do
  Mocks.reaction.to_s # FIXME
end

post '/messages/:message_id/replies' do
  # FIXME
end

# Send image
post '/channels/messaging/:channel_id/image' do
  Mocks.attachment.to_s # FIXME
end

# Send file
post '/channels/messaging/:channel_id/file' do
  Mocks.attachment.to_s # FIXME
end

post '/messages/:message_id/action' do
  # FIXME
end

# Truncate channel
post '/channels/messaging/:channel_id/truncate' do
  # FIXME
end

# Show channel members
post '/members' do
  # FIXME
end

# Add channel member
post '/channels/messaging/:channel_id' do
  # FIXME
end
