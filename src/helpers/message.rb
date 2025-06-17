class MessageType
  def self.regular
    :regular
  end

  def self.reply
    :reply
  end

  def self.ephemeral
    :ephemeral
  end

  def self.system
    :system
  end

  def self.error
    :error
  end
end

class MessageEventType
  def self.new
    'message.new'
  end

  def self.updated
    'message.updated'
  end

  def self.deleted
    'message.deleted'
  end
end

class SystemMessage
  def self.invalid_command(cmd)
    "Sorry, command #{cmd} doesn't exist. Try posting your message without the starting /"
  end

  def self.moderation
    'Message was blocked by moderation policies'
  end
end

class AttachmentActionType
  def self.send
    'send'
  end

  def self.shuffle
    'shuffle'
  end
end

def send_message_ws(response:, event_type:)
  ws_response = Mocks.message_ws
  ws_response['message'] = response['message']
  ws_response['user'] = response['message']['user']
  ws_response['cid'] = response['message']['cid']
  ws_response['channel_id'] = response['message']['cid'].split(':').last
  ws_response['created_at'] = response['message']['created_at']
  ws_response['type'] = event_type
  $ws&.send(ws_response.to_s)
end

def find_message_by_id(id)
  $message_list.detect { |msg| msg['id'] == id }
end

def update_message(request_body:, params:, delete: false)
  timestamp = unique_date
  json = request_body.empty? ? {} : JSON.parse(request_body)
  ws_event_type = delete ? MessageEventType.deleted : MessageEventType.updated
  message = find_message_by_id(params[:message_id])

  if json['message']
    message['text'] = json['message']['text']
    message['html'] = json['message']['text'].to_html
    message['message_text_updated_at'] = timestamp
  elsif json['set'] && json['set']['text']
    message['text'] = json['set']['text']
    message['html'] = json['set']['text'].to_html
    message['message_text_updated_at'] = timestamp
  elsif json['set'] && json['set']['pinned']
    message['pinned'] = json['set']['pinned']
    message['pinned_by'] = json['set']['pinned'] ? current_user : nil
    message['pinned_at'] = json['set']['pinned'] ? timestamp : nil
  elsif delete
    message['type'] = 'deleted'
    message['deleted_at'] = timestamp
    message['message_text_updated_at'] = nil
  end

  message['updated_at'] = timestamp
  response = Mocks.message
  response['message'] = message
  $message_list.delete_if { |msg| msg['id'] == params[:message_id] } if params[:hard].to_i == 1

  send_message_ws(response: response, event_type: ws_event_type)
  response.to_s
end

def create_message(request_body:, channel_id: nil)
  if $fail_messages
    return nil
  elsif $freeze_messages
    status(408)
    return nil
  end

  json = JSON.parse(request_body)
  message = json['message']
  parent_id = message['parent_id']
  quoted_message_id = message['quoted_message_id']
  channel_reply = message['show_in_channel']

  message_text = message['text'].to_s
  is_giphy = message_text.start_with?('/giphy')
  is_spam = !($forbidden_words & message_text.split).empty?
  is_invalid_command = !is_giphy && message_text.start_with?('/')
  message_text = SystemMessage.moderation if is_spam
  message_text = SystemMessage.invalid_command(message_text.sub('/', '')) if is_invalid_command

  message_type =
    if is_giphy
      MessageType.ephemeral
    elsif is_invalid_command || is_spam
      MessageType.error
    elsif channel_reply || parent_id.nil?
      MessageType.regular
    else
      MessageType.reply
    end

  timestamp = unique_date
  response = is_giphy ? Mocks.giphy : Mocks.message
  template_message = response['message']
  attachments = is_giphy ? template_message['attachments'] : message['attachments'] || template_message['attachments']

  mocked_message = mock_message(
    template_message,
    message_type: message_type,
    channel_id: channel_id,
    message_id: message['id'],
    parent_id: parent_id,
    quoted_message_id: quoted_message_id,
    show_in_channel: channel_reply,
    text: message_text,
    user: template_message['user'],
    created_at: timestamp,
    updated_at: timestamp,
    attachments: attachments,
    skip_enrich_url: json['skip_enrich_url'],
    command: is_invalid_command ? message['text'].to_s.sub('/', '') : nil,
    track_message: message_type != :error
  )

  response['message'] = mocked_message
  send_message_ws(response: response, event_type: MessageEventType.new) if message_type != :error
  response.to_s
end

def create_giphy(request_body:, message_id:)
  json = JSON.parse(request_body)
  message = find_message_by_id(message_id)
  action = json['form_data']['image_action']

  if action == AttachmentActionType.send
    message['attachments'][0]['actions'] = nil
    message['type'] = 'regular'
    message['command'] = 'giphy'
    message['text'] = ''
    message['html'] = ''
  elsif action == AttachmentActionType.shuffle
    return nil
  else
    halt(503, 'Bad request')
    return
  end

  response = Mocks.message
  response['message'] = message
  send_message_ws(response: response, event_type: MessageEventType.new)
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
  skip_enrich_url: nil,
  reply_count: 0,
  track_message: true
)
  if text
    text = text.to_s
    message['text'] = text
    message['html'] = text.to_html
  end

  if channel_id
    message['cid'] = "messaging:#{channel_id}"
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
  message['show_in_channel'] = show_in_channel if show_in_channel
  message['user'] = user if user
  message['reply_count'] = reply_count if reply_count

  if quoted_message_id
    message['quoted_message_id'] = quoted_message_id
    message['quoted_message'] = find_message_by_id(quoted_message_id)
  end

  if parent_id
    message['parent_id'] = parent_id
    parent_message = find_message_by_id(parent_id)
    parent_message['reply_count'] += 1
    parent_message['thread_participants'] ||= []
    parent_message['thread_participants'] << user unless parent_message['thread_participants'].include?(user)

    additional_response = Mocks.message_ws
    additional_response['cid'] = "messaging:#{channel_id}"
    additional_response['channel_id'] = channel_id
    additional_response['type'] = 'message.updated'
    additional_response['message'] = parent_message
    $ws&.send(additional_response.to_s)
  end

  if !skip_enrich_url && (text.include?('youtube.com/') || text.include?('unsplash.com/') || text.include?('giphy.com/'))
    json =
      if text.include?('youtube')
        Mocks.youtube_link
      elsif text.include?('unsplash')
        Mocks.unsplash_link
      else
        Mocks.giphy_link
      end
    link_attachments = json['message']['attachments']
    updated_attachments = (attachments || []) + (link_attachments || [])
    message['attachments'] = updated_attachments
  end

  $message_list << message if track_message && deleted_at.nil?
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

def create_link_preview(url)
  if url.include?('youtube')
    Mocks.youtube_link['message']['attachments'].first.to_s
  elsif url.include?('unsplash')
    Mocks.unsplash_link['message']['attachments'].first.to_s
  elsif url.include?('giphy')
    Mocks.giphy_link['message']['attachments'].first.to_s
  else
    ''
  end
end
