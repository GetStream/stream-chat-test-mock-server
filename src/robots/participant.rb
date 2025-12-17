class Participant
  def self.user
    return @user if @user

    @user = Mocks.message_ws['message']['user']
    @user['id'] = 'count_dooku'
    @user['name'] = 'Count Dooku'
    @user['image'] = 'https://vignette.wikia.nocookie.net/starwars/images/b/b8/Dooku_Headshot.jpg'
    @user
  end
end

###### MESSAGES ######

### Parameters
# `giphy`: Boolean - Pass this param if it's an ephemeral message
# `quote_last`: Boolean - Pass this param if it's a quote reply of the last message
# `quote_first`: Boolean - Pass this param if it's a quote reply of the first message
# `thread`: Boolean - Pass this param if it's a thread message
# `thread_and_channel`: Boolean - Pass this param if it's a thread message also in channel
# `image`: Integer - Pass this param if the message should contain images
# `video`: Integer - Pass this param if the message should contain videos
# `file`: Integer - Pass this param if the message should contain files
# `action`: String - Pass this param if you need to update a message (available options: `pin`, `unpin`, `edit`, `delete`)
# `hard_delete`: Boolean - Pass this param if you need to hard delete a message (requires: `action=delete`)
# `delay`: Int - Pass this param if you need the ws to be delayed by the amount of seconds

post '/participant/message' do
  timestamp = unique_date
  attachments = mock_attachments(params)
  response = Mocks.message_ws
  last_channel_message = $message_list.reverse.find { |m| m['parent_id'].nil? }
  also_in_channel = params[:thread_and_channel] == 'true'
  parent_id = params[:thread] || also_in_channel ? last_channel_message['id'] : nil
  thread_list = parent_id ? $message_list.filter { |m| m['parent_id'] == parent_id } : []
  message_type = params[:action] == 'delete' ? :deleted : params[:thread] && !also_in_channel ? :reply : :regular

  template_message = if message_type == :deleted
                       $message_list.filter { |msg| msg['user']['id'] == Participant.user['id'] }.pop
                     elsif params[:action]
                       $message_list.pop
                     elsif params[:giphy]
                       Mocks.giphy['message']
                     else
                       response['message']
                     end

  template_message['attachments'][0]['actions'] = nil if params[:giphy]
  text = ['pin', 'unpin'].include?(params[:action]) ? template_message['text'] : request.body.read

  quoted_message_id =
    if parent_id && thread_list.any? && params[:quote_first]
      thread_list.first['id']
    elsif parent_id && thread_list.any? && params[:quote_last]
      thread_list.last['id']
    elsif params[:quote_last]
      $message_list.last['id']
    elsif params[:quote_first]
      $message_list.first['id']
    end

  message = mock_message(
    template_message,
    message_type: message_type,
    channel_id: params[:action] ? template_message['channel_id'] : $current_channel_id,
    message_id: params[:action] ? template_message['id'] : unique_id,
    quoted_message_id: quoted_message_id,
    parent_id: parent_id,
    show_in_channel: params[:thread_and_channel] ? also_in_channel : params[:thread] ? false : nil,
    text: text,
    attachments: attachments,
    skip_enrich_url: false,
    user: params[:action] ? template_message['user'] : Participant.user,
    created_at: params[:action] ? template_message['created_at'] : timestamp,
    updated_at: timestamp,
    deleted_at: params[:action] == 'delete' ? timestamp : nil,
    message_text_updated_at: params[:action] == 'edit' ? timestamp : nil,
    pinned: params[:action] == 'pin',
    pinned_at: params[:action] == 'pin' ? timestamp : nil,
    pinned_by: params[:action] == 'pin' ? Participant.user : nil,
    pin_expires: nil
  )

  action_type = case params[:action]
                when 'edit', 'pin', 'unpin'
                  MessageEventType.updated
                when 'delete'
                  MessageEventType.deleted
                else
                  MessageEventType.new
                end

  response['channel_id'] = message['channel_id']
  response['cid'] = "messaging:#{message['channel_id']}"
  response['type'] = action_type
  response['message'] = message
  response['user'] = Participant.user
  response['hard_delete'] = true if params[:hard_delete] == 'true' && params[:action] == 'delete'

  if params[:delay].to_i.positive?
    Thread.new do
      sleep(params[:delay].to_i)
      $ws&.send(response.to_s)
    end
  else
    $ws&.send(response.to_s)
  end
  sync_channels
end

###### PUSH NOTIFICATIONS ######

### Parameters
# `title`: String - Push notification title
# `body`: String - Push notification body
# `rest`: String - Rest of the payload (empty, null, incorrect_type, incorrect_data, invalid)
# `bundle_id`: String - Test app bundle id
# `udid`: String - Device udid

post '/participant/push' do
  badge = 1
  mutable_content = 1
  category = 'stream.chat'
  sender = 'stream.chat'
  type = MessageEventType.new
  version = 'v2'
  id = last_message_id
  cid = "messaging:#{$current_channel_id}"

  case params[:rest]
  when 'empty'
    params[:title] = ''
    badge = 0
    mutable_content = 0
    category = ''
    sender = ''
    type = ''
    version = ''
    id = ''
    cid = ''
  when 'null'
    params[:title] = nil
    badge = nil
    mutable_content = nil
    category = nil
    sender = nil
    type = nil
    version = nil
    id = nil
    cid = nil
  when 'incorrect_type'
    params[:title] = 42
    badge = 'test'
    mutable_content = 'test'
    category = 42
    sender = 42
    type = 42
    version = 42
    id = 42
    cid = 42
  when 'incorrect_data'
    badge = -1
    mutable_content = -1
  end

  if params[:body] == 'empty'
    params[:body] = ''
  elsif params[:body] == 'null'
    params[:body] = nil
  elsif params[:body].to_i.positive?
    params[:body] = params[:body].to_i
  end

  payload = {
    aps: {
        alert: {
            title: params[:title],
            body: params[:body]
        },
        badge: badge,
        'mutable-content': mutable_content,
        category: category
    },
    stream: {
      sender: sender,
      type: type,
      version: version,
      id: id,
      cid: cid
    }
  }.to_json

  push_data_file = 'push_payload.json'
  File.write(push_data_file, payload)
  puts `xcrun simctl push #{params['udid']} #{params['bundle_id']} #{push_data_file}`
end

###### REACTIONS ######

### Parameters
# `type`: String - Pass this param to define a reaction type (available options: `like`, `love`, `sad`, `wow`, `haha`)
# `delete`: Boolean - Pass this param if you need to delete the reaction
# `delay`: Int - Pass this param if you need the ws to be delayed by the amount of seconds

post '/participant/reaction' do
  create_reaction(
    type: params[:type],
    message_id: last_message_id,
    user: Participant.user,
    delete: params[:delete],
    delay: params[:delay]
  )
  sync_channels
  ''
end

###### EVENTS ######

### Parameters
# `thread`: Boolean - Pass this param if it's a thread event

post '/participant/typing/start' do
  parent_id = nil
  if params[:thread]
    last_message = $message_list.last
    parent_id = last_message['parent_id'] || last_message['id']
  end

  create_event(
    type: 'typing.start',
    channel_id: $current_channel_id,
    parent_id: parent_id,
    user: Participant.user
  )
  ''
end

post '/participant/typing/stop' do
  parent_id = nil
  if params[:thread]
    last_message = $message_list.last
    parent_id = last_message['parent_id'] || last_message['id']
  end

  create_event(
    type: 'typing.stop',
    channel_id: $current_channel_id,
    parent_id: parent_id,
    user: Participant.user
  )
  ''
end

post '/participant/read' do
  user_reads = $channel_list['channels'][0]['read'].detect { |u| u['user']['id'] == Participant.user['id'] }
  if user_reads
    user_reads['last_read'] = unique_date
    user_reads['unread_messages'] = 0
  else
    $channel_list['channels'][0]['read'] << {
      'user' => Participant.user,
      'last_read' => unique_date,
      'unread_messages' => 0
    }
  end

  parent_id = nil
  if params[:thread]
    last_message = $message_list.last
    parent_id = last_message['parent_id'] || last_message['id']
  end

  create_event(
    type: 'message.read',
    channel_id: $current_channel_id,
    parent_id: parent_id,
    user: Participant.user
  )
  ''
end
