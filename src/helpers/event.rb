def create_event(type:, channel_id:)
  event = Mocks.event
  event['event']['type'] = type
  event['event']['channel_id'] = channel_id
  event['event']['cid'] = "messaging:#{channel_id}"
  event['created_at'] = unique_date
  event.to_s
end
