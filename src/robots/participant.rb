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
# `thread_notification`: Boolean - Also send `notification.thread_message_new` for a thread reply
# `system`: Boolean - Pass this param if it's a system message (e.g. posted by a server-side action)
# `channel_name`: String - Send a new message to the channel with this name instead of the current channel

post '/participant/message' do
  halt(400, { message: 'no current channel' }.to_s) unless find_channel_by_id($current_channel_id)

  target_channel_id = $current_channel_id
  if params[:channel_name]
    target_channel = $channel_list['channels'].detect { |c| channel_name(c['channel']) == params[:channel_name] }
    halt(400, { message: "channel #{params[:channel_name]} not found" }.to_s) unless target_channel
    target_channel_id = target_channel['channel']['id']
  end

  timestamp = unique_date
  attachments = mock_attachments(params)
  response = Mocks.message_ws
  last_channel_message = $message_list.reverse.find { |m| m['parent_id'].nil? }
  also_in_channel = params[:thread_and_channel] == 'true'
  parent_id = params[:thread] || also_in_channel ? last_channel_message['id'] : nil
  thread_list = parent_id ? $message_list.filter { |m| m['parent_id'] == parent_id } : []

  # Updates act on the newest stored message that is not deleted yet (a soft-deleted
  # message stays in the list as `type: deleted`, so it must not be picked up again).
  template_message = if params[:action] == 'delete'
                       $message_list.reverse.find { |msg| msg['user']['id'] == Participant.user['id'] && msg['deleted_at'].nil? }
                     elsif params[:action]
                       $message_list.reverse.find { |msg| msg['deleted_at'].nil? }
                     elsif params[:giphy]
                       Mocks.giphy['message']
                     else
                       response['message']
                     end
  halt(400, { message: 'no message to update' }.to_s) if template_message.nil?

  # An update keeps the stored type (`reply` stays `reply` without `thread=true`); only a delete changes it.
  message_type = if params[:action] == 'delete'
                   :deleted
                 elsif params[:action]
                   template_message['type'].to_sym
                 elsif params[:thread] && !also_in_channel
                   :reply
                 elsif params[:system] == 'true'
                   :system
                 else
                   :regular
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
    channel_id: params[:action] ? template_message['channel_id'] : target_channel_id,
    message_id: params[:action] ? template_message['id'] : unique_id,
    quoted_message_id: quoted_message_id,
    # Updates (edit/delete/pin) keep the thread linkage of the template message and must not bump the parent reply count again.
    parent_id: params[:action] ? nil : parent_id,
    reply_count: params[:action] ? template_message['reply_count'] : 0,
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
    pin_expires: nil,
    # The template of an update is already in the list and is mutated in place.
    track_message: params[:action].nil?
  )

  action_type = case params[:action]
                when 'edit', 'pin', 'unpin'
                  MessageEventType.updated
                when 'delete'
                  MessageEventType.deleted
                else
                  MessageEventType.new
                end

  if params[:action].nil? && message_type == :regular
    track_message_read_states(channel_id: message['channel_id'], message: message)
  end

  response['channel_id'] = message['channel_id']
  response['cid'] = "messaging:#{message['channel_id']}"
  response['type'] = action_type
  response['created_at'] = timestamp
  response['message'] = message
  response['user'] = Participant.user
  response['hard_delete'] = true if params[:hard_delete] == 'true' && params[:action] == 'delete'

  thread_notification = params[:thread_notification] == 'true' && parent_id && params[:action].nil?
  send_events = lambda do
    broadcast_event(response)
    broadcast_thread_message_new(message) if thread_notification
  end

  if params[:delay].to_i.positive?
    Thread.new do
      sleep(params[:delay].to_i)
      send_events.call
    end
  else
    send_events.call
  end
  sync_channels
end

# The backend also notifies thread participants about a new reply; clients update
# the thread list (latest replies, unread count) from this event only. Opt-in with
# `thread_notification=true` so existing thread tests keep receiving a single event.
def broadcast_thread_message_new(message)
  channel = find_channel_by_id(message['channel_id'])
  broadcast_event(
    'type' => 'notification.thread_message_new',
    'created_at' => message['created_at'],
    'cid' => "messaging:#{message['channel_id']}",
    'channel_id' => message['channel_id'],
    'channel_type' => 'messaging',
    'channel' => channel['channel'],
    'message' => message,
    'user' => Participant.user
  )
end

###### PUSH NOTIFICATIONS ######

### Parameters
# `platform`: String - `ios` (default) or `android`
# `title`: String - Push notification title
# `body`: String - Push notification body
# `rest`: String - Rest of the payload (empty, null, incorrect_type, incorrect_data, invalid)
# `bundle_id`: String - Test app bundle id (iOS)
# `udid`: String - Device udid (iOS)
# `component`: String - Broadcast receiver component of the test app (Android)

post '/participant/push' do
  params[:platform] == 'android' ? android_push : ios_push
end

def ios_push
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
  puts(`xcrun simctl push #{params['udid']} #{params['bundle_id']} #{push_data_file}`)
end

# Delivers the push payload to the Android test app with an adb broadcast. The receiver
# feeds it into the client SDK pipeline, whose validator requires `version`, `sender`,
# a supported `type`, `message_id`, and `cid` (or the `channel_id` and `channel_type` pair).
# The `rest` degradations mirror the iOS semantics against that contract: optional keys
# degrade without dropping the push, `invalid_*` break a required key so the push is dropped.
def android_push
  data = {
    version: 'v2',
    sender: 'stream.chat',
    type: MessageEventType.new,
    message_id: last_message_id,
    cid: "messaging:#{$current_channel_id}",
    channel_id: $current_channel_id,
    channel_type: 'messaging',
    title: params[:title],
    body: params[:body]
  }

  case params[:rest]
  when 'null'
    data.delete(:title)
    data.delete(:body)
  when 'empty'
    data[:title] = ''
    data[:body] = ''
  when 'incorrect_type'
    data[:title] = '42'
    data[:badge] = 'test'
    data[:'mutable-content'] = 'test'
  when 'incorrect_data'
    data[:badge] = '-1'
    data[:'mutable-content'] = '-1'
  when 'invalid_version'
    data[:version] = '42'
  when 'invalid_sender'
    data[:sender] = ''
  when 'invalid_type'
    data[:type] = 'bogus'
  end

  extras = data.compact.map { |key, value| "--es #{key} '#{value}'" }.join(' ')
  puts(`adb shell am broadcast -n #{params[:component]} #{extras}`)
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

###### POLLS ######

### Parameters
# `option`: String - The text of the poll option to vote for
# `answer`: String - Pass this param to add an answer (comment) instead of an option vote

post '/participant/poll_vote' do
  message = $message_list.reverse.detect { |msg| msg['poll'] }
  halt(400, { message: 'no message with a poll' }.to_s) unless message

  poll = message['poll']
  vote_data =
    if params[:answer]
      { 'answer_text' => params[:answer] }
    else
      option = poll['options'].detect { |opt| opt['text'] == params[:option] }
      halt(400, { message: "option #{params[:option]} not found" }.to_s) unless option

      { 'option_id' => option['id'] }
    end

  cast_poll_vote(
    message_id: message['id'],
    poll_id: poll['id'],
    vote_data: vote_data,
    user: Participant.user
  )
  sync_channels
  ''
end

### Parameters
# `text`: String - The text of the option the participant suggests

post '/participant/poll_option' do
  message = $message_list.reverse.detect { |msg| msg['poll'] }
  halt(400, { message: 'no message with a poll' }.to_s) unless message
  halt(400, { message: 'text param is required' }.to_s) if params[:text].to_s.empty?

  create_poll_option(poll_id: message['poll']['id'], request_body: { text: params[:text] }.to_json)
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

# Marks the current channel as delivered but not read for the participant, like the
# participant's client acknowledging the app user's messages while the channel is
# scrolled up: they turn from sent to delivered until /participant/read.
post '/participant/delivered' do
  channel = find_channel_by_id($current_channel_id)
  halt(400, { message: 'no current channel' }.to_s) unless channel

  read = mark_channel_delivered(channel: channel, user: Participant.user)
  halt(400, { message: 'no message to deliver' }.to_s) unless read

  broadcast_event(
    'type' => 'message.delivered',
    'cid' => channel['channel']['cid'],
    'channel_id' => channel['channel']['id'],
    'channel_type' => channel['channel']['type'],
    'user' => Participant.user,
    'created_at' => unique_date,
    'last_delivered_at' => read['last_delivered_at'],
    'last_delivered_message_id' => read['last_delivered_message_id']
  )
  ''
end

post '/participant/read' do
  channel = find_channel_by_id($current_channel_id)
  halt(400, { message: 'no current channel' }.to_s) unless channel

  mark_channel_read(channel: channel, user: Participant.user)

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
