def send_event_ws(response)
  ws_response = Mocks.event_ws
  ws_response['user'] = response['user']
  ws_response['cid'] = response['event']['cid']
  ws_response['channel_id'] = response['event']['channel_id']
  ws_response['created_at'] = response['created_at']
  ws_response['type'] = response['event']['type']
  $ws&.send(ws_response.to_s)
end

def create_event(type:, channel_id:, parent_id: nil, user: current_user)
  response = Mocks.event
  response['event']['type'] = type
  response['event']['cid'] = "messaging:#{channel_id}"
  response['event']['channel_id'] = channel_id
  response['created_at'] = unique_date
  response['parent_id'] = parent_id
  response['user'] = user

  send_event_ws(response)
  response.to_s
end
