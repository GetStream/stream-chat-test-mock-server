def message_creation(request_body:, channel_id: nil, event_type: :message_new)
  json = JSON.parse(request_body)
  message = json['message']
  parent_id = message['parent_id']
  quoted_message_id = message['quoted_message_id']
  channel_reply = message['show_in_channel'] || false
  message_text = message['text'].to_s

  message_type =
    if message_text.start_with?('/giphy')
      :ephemeral
    elsif channel_reply || parent_id.nil?
      :regular
    else
      :reply
    end

  if quoted_message_id && parent_id
    quoted_message_creation_in_thread(
      message,
      parent_id: parent_id,
      quoted_message_id: quoted_message_id,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  elsif quoted_message_id
    quoted_message_creation_in_channel(
      message,
      quoted_message_id: quoted_message_id,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  elsif parent_id
    message_creation_in_thread(
      message,
      parent_id: parent_id,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  else
    message_creation_in_channel(
      message,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  end
end

private

def message_creation_in_channel(message, message_type:, channel_id:, event_type: :message_new)
  text = message['text'].to_s
  message_id = message['id']
  response = message_type == :ephemeral ? Mocks.giphy : Mocks.message
  response_message = response['message']
  timestamp = unique_date
  user = response_message['user']
  attachments = message['attachments'] || response_message['attachments']

  mocked_message = mock_message(
    response_message,
    message_type: message_type,
    channel_id: channel_id,
    message_id: message_id,
    text: text,
    user: user,
    created_at: timestamp,
    updated_at: timestamp,
    attachments: attachments
  )

  response['message'] = mocked_message
  $ws&.send(response.to_s)
  response.to_s
end

def quoted_message_creation_in_channel(message, message_type:, channel_id:, quoted_message_id:, event_type: :message_new)
end

def message_creation_in_thread(message, message_type:, parent_id:, event_type: :message_new)
end

def quoted_message_creation_in_thread(message, message_type:, parent_id:, quoted_message_id:, event_type: :message_new)
end

def mock_message(
  message,
  message_id:,
  text:,
  user:,
  created_at:,
  updated_at:,
  message_type: :regular,
  channel_id: nil,
  command: nil,
  parent_id: nil,
  show_reply_in_channel: nil,
  quoted_message_id: nil,
  quoted_message: nil,
  attachments: nil,
  reply_count: 0
)
  if text
    message['text'] = text
    message['html'] = text.to_html

    if text.include?('youtube.com/') || text.include?('unsplash.com/')
      json = text.include?('youtube.com/') ? Mocks.youtube_link : Mocks.unsplash_link
      link_attachments = json['message']['attachments']
      updated_attachments = (attachments || []) + (link_attachments || [])
      message['attachments'] = updated_attachments
    end
  end

  if channel_id
    channel_type = 'messaging'
    message['cid'] = "#{channel_type}:#{channel_id}"
    message['channel_id'] = channel_id
  end

  if created_at && updated_at
    message['created_at'] = created_at
    message['updated_at'] = updated_at
  end

  message['type'] = message_type
  message['id'] = message_id if message_id
  message['command'] = command if command
  message['attachments'] = attachments if attachments
  message['parent_id'] = parent_id if parent_id
  message['show_in_channel'] = show_reply_in_channel if show_reply_in_channel
  message['quoted_message_id'] = quoted_message_id if quoted_message_id
  message['quoted_message'] = quoted_message if quoted_message
  message['user'] = user if user
  message['reply_count'] = reply_count if reply_count

  message
end
