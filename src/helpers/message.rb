def create_message(request_body:, channel_id: nil, event_type: :message_new)
  json = JSON.parse(request_body)
  message = json['message']
  parent_id = message['parent_id']
  quoted_message_id = message['quoted_message_id']
  channel_reply = message['show_in_channel']
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
    create_quoted_message_in_thread(
      message,
      parent_id: parent_id,
      quoted_message_id: quoted_message_id,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  elsif quoted_message_id
    create_quoted_message_in_channel(
      message,
      quoted_message_id: quoted_message_id,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  elsif parent_id
    create_regular_message_in_thread(
      message,
      parent_id: parent_id,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  else
    create_regular_message_in_channel(
      message,
      message_type: message_type,
      channel_id: channel_id,
      event_type: event_type
    )
  end
end

private

def create_regular_message_in_channel(message, message_type:, channel_id:, event_type: :message_new)
  timestamp = unique_date
  response = message_type == :ephemeral ? Mocks.giphy : Mocks.message
  template_message = response['message']

  mocked_message = mock_message(
    template_message,
    message_type: message_type,
    channel_id: channel_id,
    message_id: message['id'],
    text: message['text'].to_s,
    user: template_message['user'],
    created_at: timestamp,
    updated_at: timestamp,
    attachments: message['attachments'] || template_message['attachments']
  )

  response['message'] = mocked_message
  response.to_s
end

def create_quoted_message_in_channel(message, message_type:, channel_id:, quoted_message_id:, event_type: :message_new)
end

def create_regular_message_in_thread(message, message_type:, parent_id:, event_type: :message_new)
end

def create_quoted_message_in_thread(message, message_type:, parent_id:, quoted_message_id:, event_type: :message_new)
end

def mock_message(
  message,
  message_id:,
  text:,
  user:,
  created_at:,
  updated_at:,
  deleted_at: nil,
  message_text_updated_at: nil,
  pinned: nil,
  pinned_at: nil,
  pinned_by: nil,
  pin_expires: nil,
  message_type: :regular,
  channel_id: nil,
  command: nil,
  parent_id: nil,
  show_in_channel: nil,
  quoted_message_id: nil,
  attachments: nil,
  reply_count: 0
)
  if text
    text = text.to_s
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

  message['type'] = message_type
  message['pinned_at'] = pinned_at
  message['pinned_by'] = pinned_by
  message['pin_expires'] = pin_expires
  message['id'] = message_id if message_id
  message['command'] = command if command
  message['created_at'] = created_at if created_at
  message['updated_at'] = updated_at if updated_at
  message['deleted_at'] = deleted_at if deleted_at
  message['message_text_updated_at'] = message_text_updated_at if message_text_updated_at
  message['pinned'] = pinned
  message['attachments'] = attachments if attachments
  message['parent_id'] = parent_id unless parent_id.to_s.empty?
  message['show_in_channel'] = show_in_channel if show_in_channel
  message['quoted_message_id'] = quoted_message_id if quoted_message_id
  message['user'] = user if user
  message['reply_count'] = reply_count if reply_count

  $message_list << message unless deleted_at
  message
end
