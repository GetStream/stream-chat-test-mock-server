def create_event(type:, channel_id:)
  event = Mocks.event
  event_ws = Mocks.event_ws

  event_ws['type'] = type
  event_ws['channel_id'] = channel_id
  event_ws['cid'] = "messaging:#{channel_id}"
  event_ws['created_at'] = unique_date

  event['event']['type'] = type
  event['event']['channel_id'] = channel_id
  event['event']['cid'] = event_ws['cid']
  event['created_at'] = event_ws['created_at']

  $ws&.send(event_ws.to_s)
  event.to_s
end
