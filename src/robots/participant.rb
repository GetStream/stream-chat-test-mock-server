class Participant
  def self.user
    return @user if @user

    @user = Mocks.message_ws['message']['user']
    @user['id'] = 'han_solo'
    @user['name'] = 'Han Solo'
    @user['image'] = 'https://vignette.wikia.nocookie.net/starwars/images/e/e2/TFAHanSolo.png'
    @user
  end
end

###### MESSAGES ######

### Parameters
# `giphy`: Boolean - Pass this param if it's an ephemeral message
# `quote`: Boolean - Pass this param if it's a quoted message
# `thread`: Boolean - Pass this param if it's a thread message
# `thread_and_channel`: Boolean - Pass this param if it's a thread message also in channel
# `image`: Integer - Pass this param if the message should contain images
# `video`: Integer - Pass this param if the message should contain videos
# `file`: Integer - Pass this param if the message should contain files
# `action`: String - Pass this param if you need to update a message (available options: `pin`, `unpin`, `edit`, `delete`)
# `hard_delete`: Boolean - Pass this param if you need to hard delete a message (requires: `action=delete`)
post '/participant/message' do
  timestamp = unique_date
  attachments = mock_attachments(params)
  response = Mocks.message_ws
  last_message = $message_list.last
  last_channel_message = $message_list.reverse.find { |m| m['parent_id'].nil? }
  also_in_channel = params[:thread_and_channel] == 'true'

  template_message = if params[:action]
                       $message_list.pop
                     elsif params[:giphy]
                       Mocks.giphy['message']
                     else
                       response['message']
                     end

  template_message['attachments'][0]['actions'] = nil if params[:giphy]
  message_type = params[:action] == 'delete' ? :deleted : params[:thread] && !also_in_channel ? :reply : :regular
  text = ['pin', 'unpin'].include?(params[:action]) ? template_message['text'] : request.body.read

  message = mock_message(
    template_message,
    message_type: message_type,
    channel_id: params[:action] ? template_message['channel_id'] : $current_channel_id,
    message_id: params[:action] ? template_message['id'] : unique_id,
    quoted_message_id: params[:quote] ? last_message['id'] : nil,
    parent_id: params[:thread] || params[:thread_and_channel] ? last_channel_message['id'] : nil,
    show_in_channel: params[:thread_and_channel] ? also_in_channel : params[:thread] ? false : nil,
    text: text,
    attachments: attachments,
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
                  MessageType.updated
                when 'delete'
                  MessageType.deleted
                else
                  MessageType.new
                end

  response['channel_id'] = message['channel_id']
  response['cid'] = "messaging:#{message['channel_id']}"
  response['type'] = action_type
  response['message'] = message
  response['hard_delete'] = true if params[:hard_delete] == 'true' && params[:action] == 'delete'
  $ws&.send(response.to_s)
end

###### REACTIONS ######

### Parameters
# `type`: String - Pass this param to define a reaction type (available options: `like`, `love`, `sad`, `wow`, `haha`)
# `delete`: Boolean - Pass this param if you need to delete the reaction

post '/participant/reaction' do
  create_reaction(
    type: params[:type],
    message_id: last_message_id,
    user: Participant.user,
    delete: params[:delete]
  )
  ''
end

###### EVENTS ######

### Parameters
# `thread`: Boolean - Pass this param if it's a thread event

post '/participant/typing/start' do
  create_event(
    type: 'typing.start',
    channel_id: $current_channel_id,
    user: Participant.user,
    parent_id: params[:thread] ? last_message_id : nil
  )
  ''
end

post '/participant/typing/stop' do
  create_event(
    type: 'typing.stop',
    channel_id: $current_channel_id,
    user: Participant.user,
    parent_id: params[:thread] ? last_message_id : nil
  )
  ''
end

post '/participant/read' do
  $channel_list['channels'][0]['read'].detect { |u| u['user']['id'] == Participant.user['id'] }['last_read'] = unique_date
  create_event(
    type: 'message.read',
    channel_id: $current_channel_id,
    user: Participant.user,
    parent_id: params[:thread] ? last_message_id : nil
  )
  ''
end
