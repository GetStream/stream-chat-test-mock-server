# v2 carries the channel name as custom data.
def channel_name(channel)
  $api_version == :v2 ? channel.dig('custom', 'name') : channel['name']
end

def set_channel_name(channel, name)
  if $api_version == :v2
    (channel['custom'] ||= {})['name'] = name
  else
    channel['name'] = name
  end
end

def remove_channel_name(channel)
  if $api_version == :v2
    channel['custom']&.delete('name')
  else
    channel.delete('name')
  end
end

# The backend reads a channel's group from its custom `group` field.
def channel_group(channel)
  $api_version == :v2 ? channel.dig('custom', 'group') : channel['group']
end

# Every group stays in `$channel_groups` until the next /mock, so the grouped unread
# counts keep reporting a group at 0 after its last channel moves out.
def set_channel_group(channel, group)
  if $api_version == :v2
    (channel['custom'] ||= {})['group'] = group
  else
    channel['group'] = group
  end
  $channel_groups << group unless $channel_groups.include?(group)
end

# The backend reads a grouped channel's `touched_at` date from its custom data.
def channel_touched_at(channel)
  $api_version == :v2 ? channel.dig('custom', 'touched_at') : channel['touched_at']
end

def set_channel_touched_at(channel, touched_at)
  if $api_version == :v2
    (channel['custom'] ||= {})['touched_at'] = touched_at
  else
    channel['touched_at'] = touched_at
  end
end

def find_channel_by_id(id)
  $channel_list['channels'].detect { |channel| channel['channel']['id'] == id }
end

def find_channel_by_name(name)
  $channel_list['channels'].detect { |channel| channel_name(channel['channel']) == name }
end

# A new channel message moves the channel up, like on the backend.
def update_last_message_at(channel_id:, message:)
  find_channel_by_id(channel_id)['channel']['last_message_at'] = message['created_at']
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
    name = channel_name(channel['channel']).to_s.downcase
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

GROUPED_ALL_GROUP = 'all'
GROUPED_DEFAULT_LIMIT = 10
GROUPED_RELATIVE_CUTOFF = /\A(?:now-)?(\d+)d\z/.freeze

# The channels of a group, newest first. The `all` group holds every channel. Seeded
# channels share `last_message_at`, so `created_at` keeps the order stable. With a
# `query_timestamp` sort, the order follows that timestamp instead.
def grouped_channels(group, filter: nil, sort: nil)
  channels = queried_channels(nil).sort_by { |c| [c['channel']['last_message_at'].to_s, c['channel']['created_at'].to_s] }.reverse
  channels = channels.sort_by { |c| query_timestamp(c['channel']) }.reverse if query_timestamp_sort?(sort)
  channels = channels.select { |c| channel_group(c['channel']) == group } unless group == GROUPED_ALL_GROUP
  return channels if filter.nil?

  now = Time.now.utc
  channels.select { |c| grouped_filter_matches?(filter, c['channel'], now) }
end

def query_timestamp_sort?(sort)
  (sort || []).any? { |param| param['field'] == 'query_timestamp' }
end

# Like the backend, the latest of the channel's creation, its last message and its custom
# `touched_at` date.
def query_timestamp(channel)
  [channel['created_at'], channel['last_message_at'], channel_touched_at(channel)]
    .compact
    .map { |date| Time.parse(date) }
    .max
end

# Evaluates the conditions the backend accepts in a group's `filter_conditions`: `group`
# with `$eq`, `$in` and `$ne`, and `query_timestamp` with `$gte`, combined with `$and` and
# `$or`. An empty filter matches the whole group. Any other condition matches.
def grouped_filter_matches?(filter, channel, now)
  filter.all? do |field, condition|
    case field
    when '$and' then condition.all? { |child| grouped_filter_matches?(child, channel, now) }
    when '$or' then condition.any? { |child| grouped_filter_matches?(child, channel, now) }
    when 'group' then grouped_condition_matches?(condition, channel_group(channel))
    when 'query_timestamp' then query_timestamp_condition_matches?(condition, query_timestamp(channel), now)
    else true
    end
  end
end

def grouped_condition_matches?(condition, group)
  return condition == group unless condition.kind_of?(Hash)

  condition.all? do |operator, value|
    case operator
    when '$eq' then value == group
    when '$in' then value.include?(group)
    when '$ne' then value != group
    else true
    end
  end
end

def query_timestamp_condition_matches?(condition, timestamp, now)
  cutoff = condition.kind_of?(Hash) ? condition['$gte'] : nil
  return true if cutoff.nil?

  relative = GROUPED_RELATIVE_CUTOFF.match(cutoff)
  cutoff_time = relative ? now - (relative[1].to_i * 86_400) : Time.parse(cutoff)
  timestamp >= cutoff_time
end

# Like the backend, the response holds only the requested groups. `next` and `prev`
# are opaque cursors to the client, so the mock uses the page start offset as both.
# `unread_channels` counts the whole group, not only the returned page. A group's
# `filter_conditions` narrow both.
def query_grouped_channels(groups:, limit:, sort: nil)
  sync_channels
  default_limit = limit.to_i.positive? ? limit.to_i : GROUPED_DEFAULT_LIMIT
  response_groups = groups.to_h do |group, page|
    page ||= {}
    channels = grouped_channels(group, filter: page['filter_conditions'], sort: sort)
    page_limit = page['limit'].to_i.positive? ? page['limit'].to_i : default_limit
    offset = (page['next'] || page['prev']).to_i
    next_offset = offset + page_limit
    [
      group,
      {
        'channels' => channels[offset, page_limit] || [],
        'next' => next_offset < channels.count ? next_offset.to_s : nil,
        'prev' => offset.positive? ? [offset - page_limit, 0].max.to_s : nil,
        'unread_channels' => channels.count { |c| current_user_unread_messages(c) > 0 }
      }
    ]
  end
  { 'groups' => response_groups, 'duration' => '7.11ms' }.to_s
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
  set_channel_name(response['channel'], channel_name(channel['channel']))

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
