### Parameters
# `channels`: Integer - Channels count. Default 1
# `messages`: Integer - Messages count in every channel. Default 0
# `replies`: Integer - Replies count in every message. Default 0
# `messages_text`: String - Text for all the channel messages
# `replies_text`: String - Text for all the thread messages
post '/mock' do
  channels_count = params[:channels].to_i || 1
  messages_count = params[:messages].to_i || 0
  replies_count = params[:replies].to_i || 0

  timestamp = unique_date
  channel_timestamp = 0
  message_timestamp = 0
  reply_timestamp = 0

  $current_channel_id = 1.to_s
  $message_list = []
  $channel_list['channels'] = []

  channels_count.downto(1) do |i|
    channel_timestamp = update_date(timestamp: timestamp, minus_seconds: (i * 600) + 1_000_000)
    channel_template = Mocks.channels['channels'].first
    channel_template['channel']['last_message_at'] = channel_timestamp
    channel_template['channel']['id'] = i.to_s
    channel_template['channel']['name'] = i.to_s
    channel_template['channel']['cid'] = "messaging:#{i}"
    channel_template['channel']['created_at'] = channel_timestamp
    channel_template['channel']['updated_at'] = channel_timestamp
    channel_template['read'] = []
    $channel_list['channels'] << channel_template
  end

  $channel_list['channels'].each do |channel|
    messages_count.downto(1) do |i|
      message_id = unique_id
      message_timestamp = update_date(timestamp: channel_timestamp, plus_seconds: (i * 600) + 100_000)
      message_template = Mocks.message['message']
      message_template['cid'] = channel['channel']['cid']
      message_template['id'] = message_id
      message_template['created_at'] = message_timestamp
      message_template['updated_at'] = message_timestamp
      message_template['text'] = params[:messages_text] || i.to_s
      message_template['html'] = message_template['text'].to_html
      message_template['user'] = i.odd? ? current_user : Participant.user
      message_template['reply_count'] = replies_count
      channel['messages'] << message_template
      $message_list << message_template

      replies_count.downto(1) do |j|
        reply_timestamp = update_date(timestamp: message_timestamp, plus_seconds: (j * 600) + 300_000)
        reply_template = Mocks.message['message']
        reply_template['cid'] = channel['channel']['cid']
        reply_template['type'] = 'reply'
        reply_template['id'] = unique_id
        reply_template['parent_id'] = message_id
        reply_template['created_at'] = reply_timestamp
        reply_template['updated_at'] = reply_timestamp
        reply_template['text'] = params[:replies_text] || j.to_s
        reply_template['html'] = reply_template['text'].to_html
        reply_template['user'] = j.odd? ? current_user : Participant.user
        channel['messages'] << reply_template
        $message_list << reply_template
      end
    end
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
