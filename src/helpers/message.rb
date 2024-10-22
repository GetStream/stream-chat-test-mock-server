def update_message(request_body:, params:)
  timestamp = unique_date
  json = request_body.empty? ? {} : JSON.parse(request_body)
  message = $message_list.detect { |msg| msg['id'] == params[:message_id] }

  if json['message']
    message['text'] = json['message']['text']
    message['html'] = json['message']['text'].to_html
    message['message_text_updated_at'] = timestamp
  elsif json['set']
    pinned = json['set']['pinned']
    message['pinned'] = pinned
    message['pinned_by'] = pinned ? current_user : nil
    message['pinned_at'] = pinned ? timestamp : nil
  elsif params[:hard]
    message['type'] = 'deleted'
    message['deleted_at'] = timestamp
    message['message_text_updated_at'] = nil
  end

  message['updated_at'] = timestamp
  response = Mocks.message
  response['message'] = message
  $message_list.delete_if { |msg| msg['id'] == params[:message_id] } if params[:hard].to_i == 1
  response.to_s
end

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

  timestamp = unique_date
  response = message_type == :ephemeral ? Mocks.giphy : Mocks.message
  template_message = response['message']

  mocked_message = mock_message(
    template_message,
    message_type: message_type,
    channel_id: channel_id,
    message_id: message['id'],
    parent_id: parent_id,
    quoted_message_id: quoted_message_id,
    show_in_channel: channel_reply,
    text: message['text'].to_s,
    user: template_message['user'],
    created_at: timestamp,
    updated_at: timestamp,
    attachments: message['attachments'] || template_message['attachments']
  )

  response['message'] = mocked_message
  response.to_s
end

def create_giphy(request_body:, message_id:)
  json = JSON.parse(request_body)
  message = $message_list.detect { |msg| msg['id'] == message_id }

  if json['form_data']['image_action'] == 'send'
    message['attachments'][0]['actions'] = nil
    message['type'] = 'regular'
    message['command'] = 'giphy'
    message['text'] = ''
    message['html'] = ''
  end

  response = Mocks.message
  response['message'] = message
  response.to_s
end

def last_message_id
  last_message = $message_list.last
  last_message['id'] if last_message
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
  pinned: false,
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

  if parent_id
    message['parent_id'] = parent_id
    parent_message = $message_list.detect { |msg| msg['id'] == parent_id }
    parent_message['reply_count'] += 1
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
  message['show_in_channel'] = show_in_channel if show_in_channel
  message['quoted_message_id'] = quoted_message_id if quoted_message_id
  message['user'] = user if user
  message['reply_count'] = reply_count if reply_count

  $message_list << message unless deleted_at
  message
end

def mock_attachments(params)
  attachments = []

  if params[:image]
    attachment = {}
    attachment['type'] = 'image'
    attachment['image_url'] = test_asset(attachment['type'])
    params[:image].to_i.times do |i|
      attachment['title'] = "#{attachment['type']}_#{i}"
      attachments << attachment
    end
  end

  if params[:file]
    attachment = {}
    attachment['type'] = 'file'
    attachment['file_size'] = 123_456
    attachment['mime_type'] = 'application/pdf'
    attachment['asset_url'] = test_asset(attachment['type'])
    params[:file].to_i.times do |i|
      attachment['title'] = "#{attachment['type']}_#{i}"
      attachments << attachment
    end
  end

  if params[:video]
    attachment = {}
    attachment['type'] = 'video'
    attachment['mime_type'] = 'video/mp4'
    attachment['asset_url'] = test_asset(attachment['type'])
    params[:video].to_i.times do |i|
      attachment['title'] = "#{attachment['type']}_#{i}"
      attachments << attachment
    end
  end

  attachments.empty? ? nil : attachments
end
