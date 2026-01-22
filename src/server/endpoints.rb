get '/ping' do
  halt(200)
end

# Connect to WebSocket
get '/connect' do
  if Faye::WebSocket.websocket?(request.env)
    $ws = Faye::WebSocket.new(request.env)
    $ws.on(:open) { |_| send_health_check }
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
  sync_channels
  paginate_channel_list(payload: params[:payload])
end

# Show channel list (post request)
post '/channels' do
  sync_channels
  paginate_channel_list(payload: params[:payload])
end

# Show channel info
post '/channels/:channel_type/:channel_id/query' do
  paginate_message_list(params: params, request_body: request.body.read)
end

# Show thread list
get '/messages/:message_id/replies' do
  paginate_thread_list(params: params)
end

# Send event
post '/channels/messaging/:channel_id/event' do
  json = JSON.parse(request.body.read)
  create_event(type: json['event']['type'], channel_id: params[:channel_id], parent_id: json['event']['parent_id'])
end

# Read message
post '/channels/messaging/:channel_id/read' do
  create_event(type: 'message.read', channel_id: params[:channel_id])
end

# Send message
post '/channels/messaging/:channel_id/message' do
  create_message(request_body: request.body.read, channel_id: params[:channel_id])
end

# Get message
get '/messages/:message_id' do
  message = find_message_by_id(params[:message_id])
  { message: message }.to_s
end

# Update message
post '/messages/:message_id' do
  update_message(request_body: request.body.read, params: params)
end

# Delete message
delete '/messages/:message_id' do
  update_message(request_body: request.body.read, params: params, delete: true)
end

# Edit or pin message
put '/messages/:message_id' do
  update_message(request_body: request.body.read, params: params)
end

# Create draft message
post '/channels/messaging/:channel_id/draft' do
  create_draft(channel_id: params[:channel_id], request_body: request.body.read)
end

# Delete draft message
delete '/channels/messaging/:channel_id/draft' do
  delete_draft(channel_id: params[:channel_id], params: params)
end

# Send giphy
post '/messages/:message_id/action' do
  create_giphy(request_body: request.body.read, message_id: params[:message_id])
end

# Send image
post '/channels/messaging/:channel_id/image' do
  file = test_asset('image')
  { file: file }.to_s
end

# Send file
post '/channels/messaging/:channel_id/file' do
  file = request.content_type.include?('video') ? test_asset('video') : test_asset('file')
  { file: file }.to_s
end

# Send reaction
post '/messages/:message_id/reaction' do
  create_reaction(type: JSON.parse(request.body.read)['reaction']['type'], message_id: params[:message_id])
end

# Delete reaction
delete '/messages/:message_id/reaction/:reaction_type' do
  create_reaction(type: params[:reaction_type], message_id: params[:message_id], delete: true)
end

# Truncate channel
post '/channels/messaging/:channel_id/truncate' do
  truncate_channel(channel_id: params[:channel_id], request_body: request.body.read)
end

# Add/remove channel member
post '/channels/messaging/:channel_id' do
  update_members(channel_id: params[:channel_id], request_body: request.body.read)
end

# Get link preview details
get '/og' do
  create_link_preview(params[:url])
end
