def update_members(channel_id:, request_body:)
  channel = find_channel_by_id(channel_id)
  json = request_body.empty? ? {} : JSON.parse(request_body)
  remove_members = json['remove_members'] ? true : false
  member_ids = remove_members ? json['remove_members'] : json['add_members']

  unless remove_members
    member = Mocks.member
    member_ids.each do |id|
      member['user_id'] = id
      member['user']['id'] = id
      channel['members'] << member
    end
    channel['channel']['member_count'] += member_ids.count
  end

  ws_response = Mocks.ws_update_member
  member_ids.each do |id|
    member = channel['members'].detect { |m| m['user_id'] == id }
    ws_response['type'] = remove_members ? 'member.removed' : 'member.added'
    ws_response['cid'] = "messaging:#{channel_id}"
    ws_response['channel_id'] = channel_id
    ws_response['channel_type'] = 'messaging'
    ws_response['member'] = member
    ws_response['user'] = member['user']
    ws_response['created_at'] = unique_date
    $ws&.send(ws_response.to_s)
  end

  if remove_members
    member_ids.each do |id|
      channel['members'].delete_if { |m| m['user_id'] == id }
    end
    channel['channel']['member_count'] -= member_ids.count
  end

  ws_response = Mocks.ws_channel_update
  ws_response['channel_member_count'] = channel['members'].count
  ws_response['channel'] = channel['channel']
  ws_response['cid'] = "messaging:#{channel_id}"
  ws_response['channel_id'] = channel_id
  ws_response['channel_type'] = 'messaging'
  ws_response['type'] = 'channel.updated'
  ws_response['user'] = current_user
  ws_response['created_at'] = unique_date
  $ws&.send(ws_response.to_s)

  response = Mocks.update_member
  response['members'] = channel['members']
  response['channel'] = channel['channel']
  response['channel']['member_count'] = channel['members'].count
  response['member_count'] = channel['members'].count
  response.to_s
end
