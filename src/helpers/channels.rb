def find_channel_by_id(id)
  $channel_list['channels'].detect { |channel| channel['channel']['id'] == id }
end

def sync_channels
  $channel_list['channels'].each { |channel| channel['messages'] = $message_list.select { |msg| msg['cid'] == channel['channel']['cid'] } }
  $channel_list.to_s
end

def paginate_channel_list(payload: nil)
  payload = JSON.parse(payload) if payload
  return $channel_list.to_s if payload.nil? || payload['limit'].nil?

  limited_channel_list = $channel_list.dup
  channels = limited_channel_list['channels'] || []
  channel_count = channels.count - 1
  limit = payload['limit'].to_i
  offset = payload['offset'].to_i

  if !$all_channels_loaded && channel_count > limit
    $all_channels_loaded = (channel_count - limit - offset.to_i < 0)
    start_with = offset.to_i > channel_count ? channel_count : offset.to_i
    end_with = (offset.to_i + limit) < channel_count ? (offset.to_i + limit - 1) : channel_count
    limited_channel_list['channels'] = channels[start_with..end_with] || []
  end

  limited_channel_list.to_s
end

def truncate_channel(channel_id:, request_body:)
  channel = find_channel_by_id(channel_id)
  json = request_body.empty? ? {} : JSON.parse(request_body)
  truncated_at = unique_date
  truncated_by = channel['channel']['created_by']

  # Remove all messages for this channel
  $message_list.delete_if { |msg| msg['cid'] == "messaging:#{channel_id}" }

  # Update channel with truncation info
  channel['channel']['truncated_at'] = truncated_at
  channel['channel']['truncated_by'] = truncated_by
  channel['messages'] = []

  # Prepare response
  response = Mocks.truncate
  response['channel']['id'] = channel_id
  response['channel']['cid'] = "messaging:#{channel_id}"
  response['channel']['truncated_by'] = truncated_by
  response['channel']['truncated_at'] = truncated_at
  response['channel']['name'] = channel['channel']['name']

  # Send channel.truncated websocket event
  ws_response = Mocks.event_ws
  ws_response['type'] = 'channel.truncated'
  ws_response['cid'] = "messaging:#{channel_id}"
  ws_response['channel_id'] = channel_id
  ws_response['created_at'] = truncated_at
  ws_response['user'] = truncated_by
  ws_response['channel'] = response['channel']
  $ws&.send(ws_response.to_s)

  # If message provided in request, create system message
  if json['message']
    message_id = json['message']['id'] || unique_id
    message_text = json['message']['text'] || 'Channel truncated'

    truncated_message = mock_message(
      Mocks.message['message'],
      message_type: MessageType.system,
      channel_id: channel_id,
      message_id: message_id,
      text: message_text,
      user: truncated_by,
      created_at: truncated_at,
      updated_at: truncated_at,
      track_message: false
    )

    response['message'] = truncated_message

    # Send message.new websocket event for the system message
    send_message_ws(response: { 'message' => truncated_message }, event_type: MessageEventType.new)
  else
    response['message'] = nil
  end

  response.to_s
end
