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

##### Parameters
# `giphy`: Pass this param if it's an ephemeral message
# `parent_id`: Pass this param if it's a thread reply
# `quoted_message_id`: Pass this param if it's quoted message
post '/participant/message' do
  text = params[:giphy] ? nil : JSON.parse(request.body.read)['text']
  timestamp = unique_date
  message_id = unique_id
  parent_id = params[:parent_id]
  quoted_message_id = params[:quoted_message_id]
  response = Mocks.message_ws
  response_message = params[:giphy] ? Mocks.giphy['message'] : response['message']
  response_message['attachments'][0]['actions'] = nil if params[:giphy]
  message_type = params[:giphy] ? :ephemeral : :regular

  mocked_message = mock_message(
    response_message,
    message_type: message_type,
    channel_id: $current_channel_id,
    message_id: message_id,
    parent_id: parent_id,
    quoted_message_id: quoted_message_id,
    text: text,
    user: Participant.user,
    created_at: timestamp,
    updated_at: timestamp
  )

  response['message'] = mocked_message
  $ws&.send(response.to_s)
end

post '/participant/typing/start' do
  $ws&.send(Mocks.event.merge('user' => Participant.user, 'type' => 'typing.start').to_s)
end

post '/participant/typing/stop' do
  $ws&.send(Mocks.event.merge('user' => Participant.user, 'type' => 'typing.stop').to_s)
end

post '/participant/attachment' do
end

post '/participant/read' do
end

post '/participant/message/edit' do
end

post '/participant/message/delete' do
end

post '/participant/message/pin' do
end

post '/participant/message/unpin' do
end

post '/participant/reaction' do
end

post '/participant/reaction/delete' do
end

post '/participant/channel/create' do
end

post '/participant/channel/leave' do
end
