def send_event_ws(response)
  ws_response = Mocks.event_ws
  ws_response['user'] = response['user']
  ws_response['cid'] = response['event']['cid']
  ws_response['channel_id'] = response['event']['channel_id']
  ws_response['created_at'] = response['created_at']
  ws_response['type'] = response['event']['type']
  ws_response['parent_id'] = response['parent_id'] if response['parent_id']
  broadcast_event(ws_response)
end

# Event types the real backend persists for /sync replay. Transient events
# (typing, read, member, draft) are broadcast live but never replayed.
SYNC_REPLAYED_EVENT_TYPES = %w[
  channel.created
  channel.updated
  channel.deleted
  channel.hidden
  channel.visible
  channel.truncated
  notification.added_to_channel
  notification.removed_from_channel
  message.new
  message.updated
  message.deleted
  message.undeleted
  reaction.new
  reaction.updated
  reaction.deleted
].freeze

# Sends a websocket event and records a snapshot of it so POST /sync can replay it if the client
# missed it while its socket was down. The live event is sent untouched; only the recorded copy
# is stamped with the broadcast time (sub-second, matching the backend). This matters because the
# client sorts sync'd events by `created_at` and rejects the batch when the newest equals its
# `last_sync_at`, so a replayed delete or edit must carry its occurrence time rather than the
# deleted message's original `created_at`, which would equal `last_sync_at` and be dropped. The
# snapshot is taken at send time so a later in-place mutation of the message cannot change it.
def broadcast_event(event)
  if event.kind_of?(Hash) && event['cid'] && SYNC_REPLAYED_EVENT_TYPES.include?(event['type'])
    snapshot = JSON.parse(event.to_s)
    snapshot['created_at'] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')
    $sync_events << snapshot
  end
  $ws&.send(event.to_s)
end

# Whether a recorded event is at or after the client's `last_sync_at`.
# Biases toward replay: when either timestamp is missing or unparseable, include the event,
# because dropping a missed event is the failure /sync exists to prevent (the client dedupes).
def event_after_sync?(created_at, last_sync_at)
  return true unless created_at.kind_of?(String) && last_sync_at.kind_of?(String)

  Time.parse(created_at) >= Time.parse(last_sync_at)
rescue ArgumentError
  true
end

def create_event(type:, channel_id:, parent_id: nil, user: current_user)
  response = Mocks.event
  response['event']['type'] = type
  response['event']['cid'] = "messaging:#{channel_id}"
  response['event']['channel_id'] = channel_id
  response['created_at'] = unique_date
  response['parent_id'] = parent_id if parent_id
  response['user'] = user
  send_event_ws(response)
  response.to_s
end
