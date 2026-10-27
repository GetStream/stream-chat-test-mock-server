# Scheduled messages of the app user, kept in $scheduled_messages until they are sent or deleted.
# A scheduled message is created through the send message endpoint with a `scheduled_at` date
# and takes the client's message id as its own id. Once sent, it is gone from the list and the
# message reaches the channel under a new id.

SCHEDULED_MESSAGES_MAX_LEAD_SECONDS = 120 * 86_400
SCHEDULED_MESSAGES_MAX_PER_USER = 100
SCHEDULED_MESSAGES_PAGE_LIMIT = 100
SCHEDULED_MESSAGES_DEFAULT_PAGE_LIMIT = 20

def reset_scheduled_messages
  $scheduled_messages = []
  $sent_scheduled_message_ids = []
  $canceled_scheduled_message_ids = []
  $scheduled_messages_enabled = true
  $scheduled_messages_channel_limit = 10
end

def find_scheduled_message(id)
  $scheduled_messages.detect { |scheduled| scheduled['id'] == id }
end

def pending_scheduled_message?(scheduled)
  scheduled['status'] != 'failed'
end

# The backend answers with this error body, and the name in `exception_fields.reason`.
def scheduled_message_error(code:, reason:, message:, status: 400, fields: {})
  halt(
    status,
    {
      code: code,
      message: message,
      exception_fields: fields.merge(reason: reason),
      StatusCode: status,
      duration: '0.10ms',
      more_info: 'https://getstream.io/chat/docs/api_errors_response',
      details: []
    }.to_json
  )
end

def scheduled_message_not_found(id)
  halt(
    404,
    {
      code: 16,
      message: "scheduled message #{id} not found",
      StatusCode: 404,
      duration: '0.10ms',
      more_info: 'https://getstream.io/chat/docs/api_errors_response',
      details: []
    }.to_json
  )
end

def scheduled_messages_disabled_error
  scheduled_message_error(
    code: 114, reason: 'scheduled_messages_disabled', message: 'scheduled messages are not enabled for this app'
  )
end

def scheduled_message_not_editable_error(id)
  scheduled_message_error(
    code: 120,
    reason: 'scheduled_message_not_editable',
    message: "scheduled message #{id} failed to send and can only be deleted"
  )
end

# Only the app user's own scheduled messages can be changed; any other id is not found.
def own_scheduled_message(id)
  scheduled = find_scheduled_message(id)
  scheduled_message_not_found(id) unless scheduled && scheduled.dig('user', 'id') == current_user['id']
  scheduled
end

def round_up_to_minute(time)
  time = time.utc
  whole = Time.at(time.to_i - (time.to_i % 60)).utc
  whole == time ? time : whole + 60
end

# A future send time is moved to the first whole minute that is at least a minute from now.
def round_send_at(time, now)
  round_up_to_minute([time.utc, now.utc + 60].max)
end

def check_max_lead(send_at, now)
  return if send_at <= now + SCHEDULED_MESSAGES_MAX_LEAD_SECONDS

  scheduled_message_error(
    code: 116,
    reason: 'scheduled_at_too_far',
    message: 'scheduled_at must be at most 120 days from now',
    fields: { max_lead_time_seconds: SCHEDULED_MESSAGES_MAX_LEAD_SECONDS.to_s }
  )
end

# The stored content of a scheduled message: the message as the client sent it, without the
# fields the server sets.
def scheduled_message_content(message)
  content = message.reject { |key, _| %w[id cid user created_at updated_at].include?(key) }
  content['text'] = content['text'].to_s
  content['custom'] ||= {} if $api_version == :v2
  content
end

def check_scheduled_message_limits(cid)
  pending = $scheduled_messages.select { |scheduled| pending_scheduled_message?(scheduled) }
  if pending.count { |scheduled| scheduled['cid'] == cid } >= $scheduled_messages_channel_limit
    scheduled_message_error(
      code: 117,
      reason: 'scheduled_limit_channel',
      message: "you can schedule at most #{$scheduled_messages_channel_limit} messages in this channel",
      fields: { limit: $scheduled_messages_channel_limit.to_s }
    )
  end
  return if pending.count < SCHEDULED_MESSAGES_MAX_PER_USER

  scheduled_message_error(
    code: 118,
    reason: 'scheduled_limit_user',
    message: "you can schedule at most #{SCHEDULED_MESSAGES_MAX_PER_USER} messages",
    fields: { limit: SCHEDULED_MESSAGES_MAX_PER_USER.to_s }
  )
end

def store_scheduled_message(id:, cid:, content:, scheduled_at:)
  timestamp = unique_date
  scheduled = {
    'id' => id,
    'cid' => cid,
    'user' => current_user,
    'message' => content,
    'scheduled_at' => scheduled_at,
    'status' => 'scheduled',
    'created_at' => timestamp,
    'updated_at' => timestamp
  }
  $canceled_scheduled_message_ids.delete(id)
  $scheduled_messages << scheduled
  broadcast_scheduled_message_event('scheduled_message.created', scheduled)
  scheduled
end

# Answers a send message request that carries `scheduled_at`. Returns nil when the time has
# passed and the message has to go out as a normal message instead.
def schedule_message(json:, channel_id:)
  scheduled_messages_disabled_error unless $scheduled_messages_enabled

  message = json['message']
  id = message['id'] || unique_id
  cid = "messaging:#{channel_id}"
  now = Time.now.utc

  # A retry of the same request gets the stored row back, before any other check.
  existing = find_scheduled_message(id)
  if existing
    if existing['cid'] != cid
      scheduled_message_error(
        code: 119, reason: 'scheduled_message_id_taken', message: "scheduled message ID #{id} is already in use"
      )
    end
    status(201)
    return scheduled_message_send_response(existing)
  end

  if $sent_scheduled_message_ids.include?(id)
    scheduled_message_error(
      code: 123, reason: 'scheduled_message_already_sent', message: "scheduled message ID #{id} was already sent"
    )
  end

  requested_at = Time.parse(json['scheduled_at'])
  if requested_at <= now
    if $canceled_scheduled_message_ids.include?(id)
      scheduled_message_error(
        code: 124, reason: 'scheduled_message_canceled', message: "scheduled message #{id} was canceled"
      )
    end
    return nil
  end

  send_at = round_send_at(requested_at, now)
  check_max_lead(send_at, now)
  check_scheduled_message_limits(cid)

  scheduled = store_scheduled_message(
    id: id,
    cid: cid,
    content: scheduled_message_content(message),
    scheduled_at: send_at.strftime(time_format)
  )
  status(201)
  scheduled_message_send_response(scheduled)
end

# The send message response keeps its required `message`: the content as it will be sent,
# under the scheduled id. It is in no channel and the client must not show it as sent.
def scheduled_message_send_response(scheduled)
  content = scheduled['message']
  message = Mocks.message['message'].merge(
    content.slice('text', 'parent_id', 'show_in_channel', 'quoted_message_id', 'custom')
  ).merge(
    'id' => scheduled['id'],
    'cid' => scheduled['cid'],
    'type' => content['parent_id'] && !content['show_in_channel'] ? 'reply' : 'regular',
    'html' => content['text'].to_html,
    'user' => scheduled['user'],
    'attachments' => content['attachments'] || [],
    'created_at' => scheduled['created_at'],
    'updated_at' => scheduled['created_at']
  )
  { message: message, scheduled_message: scheduled, duration: '7.11ms' }.to_s
end

# The backend tells only the owner's own connections about a scheduled message.
def broadcast_scheduled_message_event(type, scheduled, extra = {})
  broadcast_event(
    {
      'type' => type,
      'created_at' => unique_date,
      'cid' => scheduled['cid'],
      'user' => current_user,
      'scheduled_message' => scheduled
    }.merge(extra)
  )
end

# Sends a scheduled message to its channel as a normal message with a new id, which emits
# `message.new`, and removes it from the list.
def send_scheduled_message(scheduled)
  $scheduled_messages.delete(scheduled)
  $sent_scheduled_message_ids << scheduled['id']
  response = post_message(
    message: scheduled['message'].merge('id' => unique_id),
    channel_id: scheduled['cid'].split(':').last
  )
  broadcast_scheduled_message_event(
    'scheduled_message.sent', scheduled, 'message_id' => response['message']['id']
  )
end

# A query filter value comes plain or wrapped in an operator like {"$eq": …} or {"$in": […]}.
def scheduled_message_filter_values(value)
  value = value.values.first if value.kind_of?(Hash)
  Array(value)
end

# Pending messages first, then failed ones, each by send time.
def sorted_scheduled_messages(cid: nil, statuses: [])
  $scheduled_messages
    .select { |scheduled| cid.nil? || scheduled['cid'] == cid }
    .select { |scheduled| statuses.empty? || statuses.include?(scheduled['status']) }
    .sort_by { |scheduled| [pending_scheduled_message?(scheduled) ? 0 : 1, Time.parse(scheduled['scheduled_at'])] }
end

def scheduled_message_channel(cid)
  channel = $channel_list['channels'].detect { |c| c['channel']['cid'] == cid }&.dig('channel')
  return nil unless channel

  image = $api_version == :v2 ? channel.dig('custom', 'image') : channel['image']
  {
    'cid' => cid,
    'type' => channel['type'] || 'messaging',
    'id' => channel['id'],
    'name' => channel_name(channel),
    'image' => image
  }.compact
end

def query_scheduled_messages(request_body:)
  json = request_body.empty? ? {} : JSON.parse(request_body)
  filter = json['filter'] || {}
  limit = json['limit'].to_i.positive? ? [json['limit'].to_i, SCHEDULED_MESSAGES_PAGE_LIMIT].min : SCHEDULED_MESSAGES_DEFAULT_PAGE_LIMIT
  offset = json['next'].to_i
  scheduled_messages = sorted_scheduled_messages(
    cid: scheduled_message_filter_values(filter['cid']).first,
    statuses: scheduled_message_filter_values(filter['status'])
  )
  page = (scheduled_messages[offset, limit] || []).map do |scheduled|
    channel = scheduled_message_channel(scheduled['cid'])
    channel ? scheduled.merge('channel' => channel) : scheduled
  end
  response = { scheduled_messages: page, duration: '7.11ms' }
  response[:next] = (offset + limit).to_s if offset + limit < scheduled_messages.count
  response.to_s
end

# A send time names the stored one when it is equal to the millisecond, or when it is the
# time first requested, which was rounded up to the stored whole minute.
def same_send_at?(requested, stored)
  (requested.to_f * 1000).floor == (stored.to_f * 1000).floor ||
    round_up_to_minute(requested) == stored
end

def update_scheduled_message(id:, request_body:)
  scheduled_messages_disabled_error unless $scheduled_messages_enabled

  json = request_body.empty? ? {} : JSON.parse(request_body)
  scheduled = own_scheduled_message(id)
  scheduled_message_not_editable_error(id) unless pending_scheduled_message?(scheduled)

  now = Time.now.utc
  stored_send_at = Time.parse(scheduled['scheduled_at'])
  send_at = stored_send_at
  if json['scheduled_at'] && !same_send_at?(Time.parse(json['scheduled_at']), stored_send_at)
    requested_at = Time.parse(json['scheduled_at'])
    if requested_at <= now
      scheduled_message_error(
        code: 115,
        reason: 'scheduled_at_too_soon',
        message: 'scheduled_at must be at least 1 minute from now',
        fields: { min_lead_time_seconds: '60' }
      )
    end
    send_at = round_send_at(requested_at, now)
    check_max_lead(send_at, now)
  end

  # An edit that changes nothing is answered without an event.
  if json['message'] || send_at != stored_send_at
    scheduled['message'] = scheduled_message_content(json['message']) if json['message']
    scheduled['scheduled_at'] = send_at.strftime(time_format)
    scheduled['updated_at'] = unique_date
    broadcast_scheduled_message_event('scheduled_message.updated', scheduled)
  end
  { scheduled_message: scheduled, duration: '7.11ms' }.to_s
end

# Cancels a scheduled message, or removes a failed one. Allowed while the feature is off.
def delete_scheduled_message(id:)
  scheduled = own_scheduled_message(id)
  $scheduled_messages.delete(scheduled)
  if pending_scheduled_message?(scheduled)
    $canceled_scheduled_message_ids << id
    scheduled = scheduled.merge('status' => 'canceled', 'updated_at' => unique_date)
  end
  broadcast_scheduled_message_event('scheduled_message.deleted', scheduled)
  { scheduled_message: scheduled, duration: '7.11ms' }.to_s
end

# Moves the send time to now and sends the message. Allowed while the feature is off.
def send_scheduled_message_now(id:)
  scheduled = own_scheduled_message(id)
  scheduled_message_not_editable_error(id) unless pending_scheduled_message?(scheduled)

  timestamp = unique_date
  scheduled['scheduled_at'] = timestamp
  scheduled['updated_at'] = timestamp
  broadcast_scheduled_message_event('scheduled_message.updated', scheduled)
  response = { scheduled_message: scheduled.dup, duration: '7.11ms' }.to_s
  send_scheduled_message(scheduled)
  response
end

# Marks a scheduled message as failed, as the backend does when it cannot send it.
def fail_scheduled_message(scheduled, failure_reason:)
  scheduled['status'] = 'failed'
  scheduled['failure_reason'] = failure_reason
  scheduled['updated_at'] = unique_date
  broadcast_scheduled_message_event('scheduled_message.failed', scheduled)
end

# The opt-in `scheduled_messages` of a channel state: the user's own messages in that channel.
# Missing when it was not requested or the feature is off.
def scheduled_messages_field(cid:, requested:)
  return {} unless requested && $scheduled_messages_enabled

  { 'scheduled_messages' => sorted_scheduled_messages(cid: cid).first(SCHEDULED_MESSAGES_PAGE_LIMIT) }
end

# The `schedule-message` capability follows the app flag, like on the backend.
def apply_schedule_message_capability(channel)
  capabilities = channel['own_capabilities']
  return unless capabilities

  capabilities.delete('schedule-message')
  capabilities << 'schedule-message' if $scheduled_messages_enabled
end
