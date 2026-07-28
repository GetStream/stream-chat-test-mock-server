# Per-user read state, kept in each channel's `read` array with the same shape
# the backend serves: `user`, `last_read`, `unread_messages`, `last_read_message_id`.
# The channel query returns it as-is, so mutating these entries is all that is
# needed for the client to render unread counts and the unread separator.

def find_read_state(channel:, user_id:)
  channel['read'].detect { |read| read['user']['id'] == user_id }
end

def seed_read_state(channel:, user:, last_read:)
  read = {
    'user' => user,
    'last_read' => last_read,
    'unread_messages' => 0,
    'last_read_message_id' => nil
  }
  channel['read'] << read
  read
end

# Matches the backend's channel message predicate: (parent_id IS NULL) OR
# (show_in_channel = true). Thread replies sent also to the channel count as
# channel messages.
def channel_visible_messages(cid:)
  $message_list.select { |msg| msg['cid'] == cid && (msg['parent_id'].nil? || msg['show_in_channel']) }
end

# A new channel message is unread for every member except its author, whose
# read state advances to the message itself, like on the real backend.
def track_message_read_states(channel_id:, message:)
  find_channel_by_id(channel_id)['read'].each do |read|
    if read['user']['id'] == message['user']['id']
      read['last_read'] = message['created_at']
      read['last_read_message_id'] = message['id']
      read['unread_messages'] = 0
    else
      read['unread_messages'] += 1
    end
  end
end

def mark_channel_read(channel:, user:)
  read = find_read_state(channel: channel, user_id: user['id']) ||
         seed_read_state(channel: channel, user: user, last_read: unique_date)
  read['last_read'] = unique_date
  read['unread_messages'] = 0
  read['last_read_message_id'] = channel_visible_messages(cid: channel['channel']['cid']).last&.dig('id')
  read
end

# Rewinds the user's read state to just before `message_id`, so that message and
# everything after it count as unread, mirroring the backend's mark-unread.
def mark_channel_unread(channel:, user:, message_id:)
  messages = channel_visible_messages(cid: channel['channel']['cid'])
  message_index = messages.index { |msg| msg['id'] == message_id }
  return nil unless message_index

  first_unread_message = messages[message_index]
  read = find_read_state(channel: channel, user_id: user['id']) ||
         seed_read_state(channel: channel, user: user, last_read: unique_date)
  read['last_read'] = update_date(timestamp: first_unread_message['created_at'], minus_seconds: 1)
  read['unread_messages'] = messages.count - message_index
  read['last_read_message_id'] = message_index.positive? ? messages[message_index - 1]['id'] : nil
  read
end