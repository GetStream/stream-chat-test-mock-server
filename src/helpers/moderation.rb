# Moderation state: user mutes, channel mutes, and blocked users, kept in globals
# so each test run (one server process per test) starts clean. Flagging is
# stateless: flag_target echoes a flag object back, which is all the clients
# need since nothing queries flags.

def own_user
  user = current_user.dup
  user['mutes'] = $user_mutes
  user['channel_mutes'] = $channel_mutes
  user
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
  {
    blocked_by_user_id: current_user['id'],
    blocked_user_id: blocked_user_id,
    created_at: timestamp,
    duration: '7.11ms'
  }.to_s
end

def unblock_user(blocked_user_id:)
  $blocked_users.delete_if { |b| b['blocked_user_id'] == blocked_user_id }
  { duration: '7.11ms' }.to_s
end
