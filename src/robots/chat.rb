### Parameters
# `channels`: Integer - Channels count. Default 1
# `messages`: Integer - Messages count in every channel. Default 0
# `replies`: Integer - Replies count in every message. Default 0
# `attachments`: Boolean - Attachments included in every message. Default false
# `messages_text`: String - Text for all the channel messages
# `replies_text`: String - Text for all the thread messages
# `dm`: Boolean - Also seed a direct-message channel between the app user and
#                 the participant: exactly two members, a member-based cid and
#                 no name, which is how the backend models 1:1 channels. Default false
# `channel_names`: String - Comma-separated names for the first channels, in channel
#                  order ("1", "2", ...). Channels without an entry keep their
#                  positional name. Lets a test seed a name it can search for
post '/mock' do
  channels_count = params[:channels].to_i || 1
  channel_names = (params[:channel_names] || '').split(',')
  messages_count = params[:messages].to_i || 0
  replies_count = params[:replies].to_i || 0

  timestamp = unique_date
  channel_timestamp = 0
  message_timestamp = 0
  reply_timestamp = 0

  $message_list = []
  $sync_events = []
  $channel_list['channels'] = []
  $reminders = []
  $polls = []
  $user_mutes = []
  $channel_mutes = []
  $blocked_users = []
  $block_hidden_channels = {}

  channels_count.downto(1) do |i|
    channel_id = SecureRandom.uuid
    channel_name = channel_names[i - 1] || i.to_s
    $current_channel_id = channel_id if i == 1
    channel_timestamp = update_date(timestamp: timestamp, minus_seconds: (i * 600) + 1_000_000)
    channel_template = Mocks.channels['channels'].first
    channel_template['channel']['last_message_at'] = channel_timestamp
    channel_template['channel']['id'] = channel_id
    channel_template['channel']['name'] = channel_name
    channel_template['channel']['cid'] = "messaging:#{channel_id}"
    channel_template['channel']['created_at'] = channel_timestamp
    channel_template['channel']['updated_at'] = channel_timestamp
    # Only the app user starts with a read entry (fully read, so seeded messages
    # render without an unread separator). The participant gets one on demand via
    # /participant/read: seeding it here would mark every seeded message as read
    # by the participant and flip the delivery status checkmarks.
    channel_template['read'] = []
    seed_read_state(channel: channel_template, user: current_user, last_read: timestamp)
    $channel_list['channels'] << channel_template
  end

  if params[:dm] == 'true'
    dm_id = "!members-#{SecureRandom.uuid}"
    dm_timestamp = update_date(timestamp: timestamp, minus_seconds: ((channels_count + 1) * 600) + 1_000_000)
    dm_channel = Mocks.channels['channels'].first
    dm_channel['channel']['id'] = dm_id
    dm_channel['channel']['cid'] = "messaging:#{dm_id}"
    dm_channel['channel'].delete('name')
    dm_channel['channel']['last_message_at'] = dm_timestamp
    dm_channel['channel']['created_at'] = dm_timestamp
    dm_channel['channel']['updated_at'] = dm_timestamp
    dm_channel['members'] = dm_channel['members'].select do |member|
      [current_user['id'], Participant.user['id']].include?(member['user_id'])
    end
    dm_channel['channel']['member_count'] = dm_channel['members'].count
    dm_channel['read'] = []
    seed_read_state(channel: dm_channel, user: current_user, last_read: timestamp)
    $channel_list['channels'] << dm_channel
  end

  $channel_list['channels'].each do |channel|
    messages_count.times do |i|
      message_id = unique_id
      message_timestamp = update_date(timestamp: channel_timestamp, plus_seconds: (i * 600) + 100_000)
      message_template = Mocks.message['message']
      message_template['cid'] = channel['channel']['cid']
      message_template['id'] = message_id
      message_template['created_at'] = message_timestamp
      message_template['updated_at'] = message_timestamp
      message_template['text'] = params[:messages_text] || (i + 1).to_s
      message_template['html'] = message_template['text'].to_html
      message_template['user'] = (i + 1).odd? ? current_user : Participant.user
      message_template['reply_count'] = replies_count
      message_template['attachments'] = mock_attachments(image: 1, video: 1, file: 1) if params[:attachments]
      channel['messages'] << message_template
      $message_list << message_template

      replies_count.times do |j|
        reply_timestamp = update_date(timestamp: message_timestamp, plus_seconds: (j * 600) + 300_000)
        reply_template = Mocks.message['message']
        reply_template['cid'] = channel['channel']['cid']
        reply_template['type'] = 'reply'
        reply_template['id'] = unique_id
        reply_template['parent_id'] = message_id
        reply_template['created_at'] = reply_timestamp
        reply_template['updated_at'] = reply_timestamp
        reply_template['text'] = params[:replies_text] || (j + 1).to_s
        reply_template['html'] = reply_template['text'].to_html
        reply_template['user'] = (j + 1).odd? ? current_user : Participant.user
        message_template['attachments'] = mock_attachments(image: 1, video: 1, file: 1) if params[:attachments]
        channel['messages'] << reply_template
        $message_list << reply_template
      end
    end
    channel['channel']['last_message_at'] = message_timestamp if messages_count.positive?
  end

  ''
end

post '/fail_messages' do
  $fail_messages = true
  ''
end

post '/freeze_messages' do
  $freeze_messages = true
  ''
end

post '/delay_messages' do
  $delay_messages = params[:delay].to_i.positive? ? params[:delay].to_i : 5
  ''
end

# Truncates the current channel as a server-side action, reusing the same helper
# as the client-initiated truncate endpoint. The app under test only receives the
# `channel.truncated` websocket event (and the system message when requested).
post '/truncate_channel' do
  request_body = params[:with_message] == 'true' ? '{"message":{}}' : ''
  truncate_channel(channel_id: $current_channel_id, request_body: request_body)
  ''
end

# Adds or removes a member on the current channel as a server-side action, reusing
# the same helper as the client-initiated channel update endpoint. The app under test
# receives the `member.added`/`member.removed` and `channel.updated` websocket events.
post '/add_member' do
  update_members(channel_id: $current_channel_id, request_body: { add_members: [params[:user_id]] }.to_json)
  ''
end

post '/remove_member' do
  update_members(channel_id: $current_channel_id, request_body: { remove_members: [params[:user_id]] }.to_json)
  ''
end

# Seeds a server-side reminder on the last message for the app user, so tests can
# open the reminders screen without creating the reminder through the app.
### Parameters
# `remind_at`: Integer - Offset in seconds from now for the scheduled reminder.
#                        Omit it for a save-for-later reminder without a due date.
post '/create_reminder' do
  remind_at = params[:remind_at] ? update_date(timestamp: unique_date, plus_seconds: params[:remind_at].to_i) : nil
  create_reminder(message_id: last_message_id, remind_at: remind_at)
  ''
end
