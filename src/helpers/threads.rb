# Builds the thread objects served by the threads query from the tracked messages:
# every channel message with replies is a thread.

def query_threads(reply_limit:)
  parents = $message_list.select do |msg|
    msg['parent_id'].nil? && $message_list.any? { |reply| reply['parent_id'] == msg['id'] }
  end
  threads = parents.map { |parent| build_thread(parent: parent, reply_limit: reply_limit) }
  threads.sort_by! { |thread| thread['last_message_at'] }.reverse!
  { threads: threads, duration: '7.11ms' }.to_s
end

def build_thread(parent:, reply_limit:)
  replies = $message_list.select { |msg| msg['parent_id'] == parent['id'] }
  participants = replies.map { |reply| reply['user'] }.uniq { |user| user['id'] }
  # Seeded messages carry only `cid`; `channel_id` is not reliably set on them.
  channel = find_channel_by_id(parent['cid'].split(':').last)
  {
    'channel_cid' => parent['cid'],
    'channel' => channel['channel'],
    'parent_message_id' => parent['id'],
    'parent_message' => parent,
    'title' => parent['text'],
    'created_at' => replies.first['created_at'],
    'updated_at' => replies.last['created_at'],
    'last_message_at' => replies.last['created_at'],
    'created_by_user_id' => replies.first['user']['id'],
    'created_by' => replies.first['user'],
    'participant_count' => participants.count,
    'reply_count' => replies.count,
    'latest_replies' => replies.last(reply_limit),
    'thread_participants' => participants.map { |user| build_thread_participant(parent: parent, user: user, replies: replies) }
  }
end

# Mirrors the fields the real backend sends for a thread participant. Clients generated from the
# OpenAPI spec require channel_cid, created_at, last_read_at and custom.
def build_thread_participant(parent:, user:, replies:)
  user_replies = replies.select { |reply| reply['user']['id'] == user['id'] }
  {
    'channel_cid' => parent['cid'],
    'thread_id' => parent['id'],
    'user_id' => user['id'],
    'user' => user,
    'created_at' => user_replies.first['created_at'],
    'last_read_at' => user_replies.last['created_at'],
    'last_thread_message_at' => user_replies.last['created_at'],
    'custom' => {}
  }
end
