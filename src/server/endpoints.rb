get '/ping' do
  halt(200)
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
  channels_response
end

post '/channels' do
  channels_response
end

def channels_response
  $channel_list['channels'].each { |channel| channel['messages'] = $message_list.select { |msg| msg['cid'] == channel['channel']['cid'] } }
  $channel_list.to_s
end

# Show channel info
post '/channels/:channel_type/:channel_id/query' do
  $channel_list['channels'].detect { |channel| channel['channel']['id'] == params[:channel_id] }.to_s
end

# Show thread list
get '/messages/:message_id/replies' do
  thread_list = $message_list.select { |msg| msg['parent_id'] == params[:message_id] }
  { messages: thread_list }.to_s
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

# Get link preview details
get '/og' do
  create_link_preview(params[:url])
end
