# Moderation state: user mutes, channel mutes, and blocked users, kept in globals
# so each test run (one server process per test) starts clean. Flagging is
# stateless: flag_target echoes a flag object back, which is all the clients
# need since nothing queries flags.

def own_user
  current_user.dup.merge(live_own_user_state)
end

# The client applies every own-user push as a full update, so any payload that
# carries `me` (the health check included) has to embed the live moderation
# state or it wipes what a mute or block endpoint just changed.
def live_own_user_state
  {
    'mutes' => $user_mutes,
    'channel_mutes' => $channel_mutes,
    'blocked_user_ids' => $blocked_users.map { |b| b['blocked_user_id'] }
  }
end

def find_user_by_id(user_id)
  return current_user if user_id == current_user['id']
  return Participant.user if user_id == Participant.user['id']

  member = $channel_list['channels'].flat_map { |c| c['members'] || [] }.detect { |m| m['user_id'] == user_id }
  member ? member['user'] : { 'id' => user_id, 'role' => 'user', 'banned' => false, 'online' => false }
end

def send_mutes_updated_ws(type)
  broadcast_event(
    'type' => type,
    'created_at' => unique_date,
    'me' => own_user
  )
end

def mute_user(target_id:)
  timestamp = unique_date
  mute = {
    'user' => current_user,
    'target' => find_user_by_id(target_id),
    'created_at' => timestamp,
    'updated_at' => timestamp
  }
  # The backend upserts a repeated mute instead of duplicating it.
  $user_mutes.delete_if { |existing| existing['target']['id'] == target_id }
  $user_mutes << mute
  send_mutes_updated_ws('notification.mutes_updated')
  { mute: mute, own_user: own_user, duration: '7.11ms' }.to_s
end

def unmute_user(target_id:)
  $user_mutes.delete_if { |m| m['target']['id'] == target_id }
  send_mutes_updated_ws('notification.mutes_updated')
  { duration: '7.11ms' }.to_s
end

def mute_channel(channel_cids:)
  timestamp = unique_date
  channel_cids.each do |cid|
    channel = find_channel_by_id(cid.split(':').last)
    halt(400, { message: "channel #{cid} not found" }.to_s) unless channel

    # The backend upserts a repeated mute instead of duplicating it.
    $channel_mutes.delete_if { |existing| existing['channel']['cid'] == cid }
    $channel_mutes << {
      'user' => current_user,
      'channel' => channel['channel'],
      'created_at' => timestamp,
      'updated_at' => timestamp
    }
  end
  send_mutes_updated_ws('notification.channel_mutes_updated')
  { duration: '7.11ms' }.to_s
end

def unmute_channel(channel_cids:)
  $channel_mutes.delete_if { |m| channel_cids.include?(m['channel']['cid']) }
  send_mutes_updated_ws('notification.channel_mutes_updated')
  { duration: '7.11ms' }.to_s
end

def flag_target(request_body:)
  json = request_body.empty? ? {} : JSON.parse(request_body)
  timestamp = unique_date
  flag = {
    'user' => current_user,
    'created_at' => timestamp,
    'updated_at' => timestamp,
    'created_by_automod' => false
  }
  flag['target_message_id'] = json['target_message_id'] if json['target_message_id']
  flag['target_user'] = find_user_by_id(json['target_user_id']) if json['target_user_id']
  { flag: flag, duration: '7.11ms' }.to_s
end

def block_user(blocked_user_id:)
  timestamp = unique_date
  block = {
    'user_id' => current_user['id'],
    'blocked_user_id' => blocked_user_id,
    'created_at' => timestamp
  }
  $blocked_users << block
  hide_direct_message_channels(blocked_user_id)
  {
    blocked_by_user_id: current_user['id'],
    blocked_user_id: blocked_user_id,
    created_at: timestamp,
    duration: '7.11ms'
  }.to_s
end

def unblock_user(blocked_user_id:)
  $blocked_users.delete_if { |b| b['blocked_user_id'] == blocked_user_id }
  show_direct_message_channels(blocked_user_id)
  { duration: '7.11ms' }.to_s
end

# The backend hides every channel whose exact members are the blocking and the
# blocked user, and unhides those same channels on unblock. The block remembers
# which channels it hid so an unblock does not surface a channel the user had
# hidden independently.
def hide_direct_message_channels(blocked_user_id)
  hidden_cids = []
  channels_with_exact_members(blocked_user_id).each do |channel|
    next if channel['channel']['hidden']

    channel['channel']['hidden'] = true
    hidden_cids << channel['channel']['cid']
    send_channel_visibility_ws(channel: channel, type: 'channel.hidden')
  end
  $block_hidden_channels[blocked_user_id] = hidden_cids
end

def show_direct_message_channels(blocked_user_id)
  ($block_hidden_channels.delete(blocked_user_id) || []).each do |cid|
    channel = find_channel_by_id(cid.split(':').last)
    next unless channel && channel['channel']['hidden']

    channel['channel']['hidden'] = false
    send_channel_visibility_ws(channel: channel, type: 'channel.visible')
  end
end

def channels_with_exact_members(user_id)
  expected_ids = [current_user['id'], user_id].sort
  $channel_list['channels'].select do |channel|
    (channel['members'] || []).map { |m| m['user_id'] }.sort == expected_ids
  end
end

def send_channel_visibility_ws(channel:, type:)
  ws_response = Mocks.event_ws
  ws_response['type'] = type
  ws_response['cid'] = channel['channel']['cid']
  ws_response['channel_id'] = channel['channel']['id']
  ws_response['created_at'] = unique_date
  ws_response['user'] = current_user
  ws_response['channel'] = channel['channel']
  ws_response['clear_history'] = false if type == 'channel.hidden'
  broadcast_event(ws_response)
end
