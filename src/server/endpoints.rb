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
  $channel_list['channels'].each { |channel| channel['messages'] = $message_list }
  $channel_list.to_s
end

# Show channel info
post '/channels/:channel_type/:channel_id/query' do
  $channel_list['channels'].detect { |channel| channel['channel']['id'] == params[:channel_id] }.to_s
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
  update_message(request_body: request.body.read, params: params)
end

# Delete message
delete '/messages/:message_id' do
  update_message(request_body: request.body.read, params: params)
end

# Pin message
put '/messages/:message_id' do
  update_message(request_body: request.body.read, params: params)
end

# Send giphy
post '/messages/:message_id/action' do
  create_giphy(request_body: request.body.read, message_id: params[:message_id])
end

# Send image
post '/channels/messaging/:channel_id/image' do
  status 500
end

# Send file
post '/channels/messaging/:channel_id/file' do
  status 500
end

# Send reaction
post '/messages/:message_id/reaction' do
  status 500
end

# Update reaction
post '/messages/:message_id/reaction/:reaction_type' do
  status 500
end

# Show thread list
post '/messages/:message_id/replies' do
  status 500
end

# Truncate channel
post '/channels/messaging/:channel_id/truncate' do
  status 500
end

# Show channel members
post '/members' do
  status 500
end

# Add channel member
post '/channels/messaging/:channel_id' do
  status 500
end
