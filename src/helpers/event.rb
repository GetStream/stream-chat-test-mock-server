def create_event(type:, channel_id:, user: current_user, parent_id: nil, response: Mocks.event)
  cid = "messaging:#{channel_id}"
  if user == current_user
    response['event']['type'] = type
    response['event']['cid'] = cid
    response['event']['channel_id'] = channel_id
  else
    response['type'] = type
    response['cid'] = cid
    response['channel_id'] = channel_id
  end
  response['created_at'] = unique_date
  response['parent_id'] = parent_id
  response['user'] = user
  response.to_s
end
