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

# Show WebSocket connection status
get '/ws/status' do
  { connected: !$ws.nil? }.to_json
end

# Synchronize: replay the events broadcast since `last_sync_at` for the requested channels,
# so a client that missed live events while its socket was down recovers them on reconnect.
post '/sync' do
  body = request.body.read
  json = body.empty? ? {} : JSON.parse(body)
  cids = json['channel_cids'] || []
  last_sync_at = json['last_sync_at']
  events = $sync_events.select do |event|
    cids.include?(event['cid']) && event_after_sync?(event['created_at'], last_sync_at)
  end
  { events: events }.to_s
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

# Mark channel read
post '/channels/messaging/:channel_id/read' do
  channel = find_channel_by_id(params[:channel_id])
  halt(400, { message: "channel #{params[:channel_id]} not found" }.to_s) unless channel

  mark_channel_read(channel: channel, user: current_user)
  create_event(type: 'message.read', channel_id: params[:channel_id])
end

# Mark channels delivered
post '/channels/delivered' do
  { duration: '7.11ms' }.to_s
end

# Mark channel unread from a message on
post '/channels/messaging/:channel_id/unread' do
  json = JSON.parse(request.body.read)
  channel = find_channel_by_id(params[:channel_id])
  read = mark_channel_unread(channel: channel, user: current_user, message_id: json['message_id'])
  halt(400, { message: "message #{json['message_id']} not found" }.to_s) unless read

  broadcast_event(
    'type' => 'notification.mark_unread',
    'created_at' => unique_date,
    'cid' => channel['channel']['cid'],
    'channel_type' => 'messaging',
    'channel_id' => params[:channel_id],
    'user' => current_user,
    'first_unread_message_id' => json['message_id'],
    'last_read_message_id' => read['last_read_message_id'],
    'last_read_at' => read['last_read'],
    'unread_messages' => read['unread_messages'],
    'unread_channels' => 1,
    'total_unread_count' => read['unread_messages']
  )
  { duration: '7.11ms' }.to_s
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
  upload_response('image').to_json
end

# Send file
post '/channels/messaging/:channel_id/file' do
  upload_response(request.content_type.include?('video') ? 'video' : 'file').to_json
end

# Send image (v2)
post '/api/v2/chat/channels/messaging/:channel_id/image' do
  upload_response('image').to_json
end

# Send file (v2)
post '/api/v2/chat/channels/messaging/:channel_id/file' do
  upload_response(request.content_type.include?('video') ? 'video' : 'file').to_json
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

# Truncate channel (v2)
post '/api/v2/chat/channels/messaging/:channel_id/truncate' do
  truncate_channel(channel_id: params[:channel_id], request_body: request.body.read)
end

# Add/remove channel member
post '/channels/messaging/:channel_id' do
  update_members(channel_id: params[:channel_id], request_body: request.body.read)
end

# Delete channel
delete '/channels/messaging/:channel_id' do
  channel = find_channel_by_id(params[:channel_id])
  halt(400, { message: "channel #{params[:channel_id]} not found" }.to_s) unless channel

  timestamp = unique_date
  channel['channel']['deleted_at'] = timestamp
  $channel_list['channels'].delete(channel)
  $message_list.delete_if { |msg| msg['cid'] == channel['channel']['cid'] }
  # The participant and chat robots act on the current channel; leaving the pointer
  # on the deleted channel would break every robot call after the deletion.
  if params[:channel_id] == $current_channel_id
    $current_channel_id = $channel_list['channels'].first&.dig('channel', 'id')
  end

  broadcast_event(
    'type' => 'channel.deleted',
    'created_at' => timestamp,
    'cid' => channel['channel']['cid'],
    'channel_type' => 'messaging',
    'channel_id' => params[:channel_id],
    'channel' => channel['channel'],
    'user' => current_user
  )
  { channel: channel['channel'], duration: '7.11ms' }.to_s
end

# Show pinned messages
get '/channels/messaging/:channel_id/pinned_messages' do
  payload = params[:payload] ? JSON.parse(params[:payload]) : {}
  pinned_messages = $message_list.select do |msg|
    msg['cid'] == "messaging:#{params[:channel_id]}" && msg['pinned']
  end
  pinned_messages = pinned_messages.last(payload['limit'].to_i) if payload['limit']
  { messages: pinned_messages, duration: '7.11ms' }.to_s
end

# Search messages
get '/search' do
  payload = JSON.parse(params[:payload])
  { results: search_messages(payload).map { |msg| { message: msg } }, duration: '7.11ms' }.to_s
end

# Show thread list
post '/threads' do
  body = request.body.read
  json = body.empty? ? {} : JSON.parse(body)
  query_threads(reply_limit: (json['reply_limit'] || 2).to_i)
end

# Query message reactions
post '/messages/:message_id/reactions' do
  body = request.body.read
  json = body.empty? ? {} : JSON.parse(body)
  filter_type = json.dig('filter', 'type')
  filter_type = filter_type.values.first if filter_type.kind_of?(Hash)
  message = find_message_by_id(params[:message_id])
  halt(400, { message: "message #{params[:message_id]} not found" }.to_s) unless message

  reactions = message['latest_reactions'] || []
  reactions = reactions.select { |reaction| reaction['type'] == filter_type } if filter_type
  { reactions: reactions, duration: '7.11ms' }.to_s
end

# Flag message or user
post '/moderation/flag' do
  flag_target(request_body: request.body.read)
end

# Unflag message or user
post '/moderation/unflag' do
  flag_target(request_body: request.body.read)
end

# Mute user
post '/moderation/mute' do
  mute_user(target_id: JSON.parse(request.body.read)['target_id'])
end

# Unmute user
post '/moderation/unmute' do
  unmute_user(target_id: JSON.parse(request.body.read)['target_id'])
end

# Mute channel
post '/moderation/mute/channel' do
  mute_channel(channel_cids: JSON.parse(request.body.read)['channel_cids'])
end

# Unmute channel
post '/moderation/unmute/channel' do
  unmute_channel(channel_cids: JSON.parse(request.body.read)['channel_cids'])
end

# Block user
post '/users/block' do
  block_user(blocked_user_id: JSON.parse(request.body.read)['blocked_user_id'])
end

# Unblock user
post '/users/unblock' do
  unblock_user(blocked_user_id: JSON.parse(request.body.read)['blocked_user_id'])
end

# Show blocked users
get '/users/block' do
  { blocks: $blocked_users, duration: '7.11ms' }.to_s
end

# Query message reminders
post '/reminders/query' do
  { reminders: $reminders, duration: '7.11ms' }.to_s
end

# Create message reminder
post '/messages/:message_id/reminders' do
  create_reminder(message_id: params[:message_id], remind_at: JSON.parse(request.body.read)['remind_at'])
end

# Update message reminder
patch '/messages/:message_id/reminders' do
  update_reminder(message_id: params[:message_id], remind_at: JSON.parse(request.body.read)['remind_at'])
end

# Delete message reminder
delete '/messages/:message_id/reminders' do
  delete_reminder(message_id: params[:message_id])
end

# Create poll
post '/polls' do
  create_poll(request_body: request.body.read)
end

# Update poll
put '/polls' do
  update_poll(request_body: request.body.read)
end

# Query polls
post '/polls/query' do
  { polls: $polls, duration: '7.11ms' }.to_s
end

# Get poll
get '/polls/:poll_id' do
  poll = find_poll(params[:poll_id])
  halt(400, { message: "poll #{params[:poll_id]} not found" }.to_s) unless poll

  { poll: poll, duration: '7.11ms' }.to_s
end

# Partially update poll
patch '/polls/:poll_id' do
  partial_update_poll(poll_id: params[:poll_id], request_body: request.body.read)
end

# Delete poll
delete '/polls/:poll_id' do
  delete_poll(poll_id: params[:poll_id])
end

# Create poll option
post '/polls/:poll_id/options' do
  create_poll_option(poll_id: params[:poll_id], request_body: request.body.read)
end

# Update poll option
put '/polls/:poll_id/options' do
  update_poll_option(poll_id: params[:poll_id], request_body: request.body.read)
end

# Delete poll option
delete '/polls/:poll_id/options/:option_id' do
  delete_poll_option(poll_id: params[:poll_id], option_id: params[:option_id])
end

# Query poll votes
post '/polls/:poll_id/votes' do
  query_poll_votes(poll_id: params[:poll_id], request_body: request.body.read)
end

# Cast poll vote or answer
post '/messages/:message_id/polls/:poll_id/vote' do
  json = JSON.parse(request.body.read)
  cast_poll_vote(
    message_id: params[:message_id],
    poll_id: params[:poll_id],
    vote_data: json['vote'] || {}
  )
end

# Remove poll vote
delete '/messages/:message_id/polls/:poll_id/vote/:vote_id' do
  remove_poll_vote(
    message_id: params[:message_id],
    poll_id: params[:poll_id],
    vote_id: params[:vote_id]
  )
end

# Get link preview details
get '/og' do
  create_link_preview(params[:url])
end
