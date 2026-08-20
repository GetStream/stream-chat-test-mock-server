def find_channel_by_id(id)
  $channel_list['channels'].detect { |channel| channel['channel']['id'] == id }
end

def sync_channels
  $channel_list['channels'].each { |channel| channel['messages'] = $message_list.select { |msg| msg['cid'] == channel['channel']['cid'] } }
  $channel_list.to_s
end

# The backend excludes hidden channels from a query by default and matches
# `$autocomplete` search conditions on `name` and `member.user.name`. The tests
# only need enough of that to prove a channel is matched by its name, so every
# other condition in the filter keeps being ignored.
def queried_channels(filter)
  channels = ($channel_list['channels'] || []).reject { |c| c['channel']['hidden'] }
  name_terms = autocomplete_terms(filter, 'name')
  member_terms = autocomplete_terms(filter, 'member.user.name')
  return channels if name_terms.empty? && member_terms.empty?

  channels.select do |channel|
    name = channel['channel']['name'].to_s.downcase
    member_names = (channel['members'] || []).map { |m| m.dig('user', 'name').to_s.downcase }
    name_terms.any? { |term| name.include?(term.downcase) } ||
      member_terms.any? { |term| member_names.any? { |n| n.include?(term.downcase) } }
  end
end

def autocomplete_terms(node, field)
  case node
  when Array
    node.flat_map { |item| autocomplete_terms(item, field) }
  when Hash
    node.flat_map do |key, value|
      if key == field && value.kind_of?(Hash) && value['$autocomplete']
        [value['$autocomplete']]
      else
        autocomplete_terms(value, field)
      end
    end
  else
    []
  end
end

def search_query?(filter)
  autocomplete_terms(filter, 'name').any? || autocomplete_terms(filter, 'member.user.name').any?
end

def paginate_channel_list(payload: nil)
  payload = JSON.parse(payload) if payload
  filter = payload && payload['filter_conditions']
  limited_channel_list = $channel_list.dup
  limited_channel_list['channels'] = queried_channels(filter)
  # A search query is never sliced and leaves the pagination flag alone, so
  # channel search cannot disturb the paging state of the unfiltered queries.
  return limited_channel_list.to_s if payload.nil? || payload['limit'].nil? || search_query?(filter)

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
  broadcast_event(ws_response)

  # If message provided in request, create system message
  if json['message']
    message_id = json['message']['id'] || unique_id
    message_text = json['message']['text'] || 'Channel truncated'

    # Persist the system message (track_message: true) so it survives a channel re-query.
    # The backend keeps the truncation system message, so a client that re-watches the
    # channel after `channel.truncated` gets it back. Without persistence the re-query
    # rebuilds `channel['messages']` from an empty `$message_list` and wipes the message
    # the client just received over the websocket, which flakes the assertion.
    truncated_message = mock_message(
      Mocks.message['message'],
      message_type: MessageType.system,
      channel_id: channel_id,
      message_id: message_id,
      text: message_text,
      user: truncated_by,
      created_at: truncated_at,
      updated_at: truncated_at,
      track_message: true
    )

    response['message'] = truncated_message

    # Send message.new websocket event for the system message
    send_message_ws(response: { 'message' => truncated_message }, event_type: MessageEventType.new)
  else
    response['message'] = nil
  end

  response.to_s
end
