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
require_relative 'helpers/message'

$ws = nil
$current_channel_id = Mocks.event['channel_id']

set :port, ARGV[0] || 4568

before do
  content_type :json
  request.body.rewind
end

Thread.new do
  loop do
    sleep 3
    $ws&.send(Mocks.health_check.merge('me' => nil).to_s)
  end
end

get '/connect' do
  if Faye::WebSocket.websocket?(request.env)
    $ws = Faye::WebSocket.new(request.env)
    $ws.on(:open) { |_| $ws.send(Mocks.health_check.to_s) }
    $ws.on(:close) { $ws = nil }
    $ws.rack_response
  end
end

post '/sync' do
  { events: [] }.to_json
end

post '/channels/messaging/:channel_id/event' do
  Mocks.event.to_s # FIXME
end

# Read channels
get '/channels' do
  Mocks.channels.to_s # FIXME
end

post '/channels/messaging/:channel_id' do
  Mocks.channels.to_s # FIXME
end

post '/channels/:channel_type/:channel_id/query' do
  # FIXME: NOW
end

# Read message
post '/channels/messaging/:channel_id/read' do
  Mocks.event.to_s # FIXME: NOW
end

# Sent message
post '/channels/messaging/:channel_id/message' do
  message_creation(request_body: request.body.read, channel_id: params[:channel_id])
end

# Updated message
post '/messages/:message_id' do
  # FIXME: NOW
end

# Sent reaction
post '/messages/:message_id/reaction' do
  Mocks.reaction.to_s # FIXME: NOW
end

# Updated reaction
post '/messages/:message_id/reaction/:reaction_type' do
  Mocks.reaction.to_s # FIXME: NOW
end

post '/messages/:message_id/replies' do
  # FIXME
end

# Sent image
post '/channels/messaging/:channel_id/image' do
  Mocks.attachment.to_s # FIXME
end

# Sent file
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

post '/members' do
  # FIXME
end
