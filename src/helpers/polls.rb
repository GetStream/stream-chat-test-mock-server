# Polls live in $polls and are embedded on their message under `poll` by reference,
# so an in-place poll mutation is visible in every later message list response
# without re-linking. `own_votes` holds only the app user's votes: the poll payload
# is always serialized from the app user's point of view, and participant votes
# reach the app user through the vote events instead.

class PollEventType
  def self.updated
    'poll.updated'
  end

  def self.closed
    'poll.closed'
  end

  def self.deleted
    'poll.deleted'
  end

  def self.vote_casted
    'poll.vote_casted'
  end

  def self.vote_changed
    'poll.vote_changed'
  end

  def self.vote_removed
    'poll.vote_removed'
  end
end

def find_poll(poll_id)
  $polls.detect { |poll| poll['id'] == poll_id }
end

def find_poll_message(poll_id)
  $message_list.detect { |msg| msg.dig('poll', 'id') == poll_id }
end

def poll_option(text)
  { 'id' => unique_id, 'text' => text.to_s }
end

# Answer votes carry `is_answer` and `answer_text` on top of this shape, with an
# empty `option_id`: clients parse `option_id` as a required non-null string.
def poll_vote(poll_id:, option_id:, user:, timestamp:)
  {
    'id' => unique_id,
    'poll_id' => poll_id,
    'option_id' => option_id,
    'user' => user,
    'user_id' => user['id'],
    'created_at' => timestamp,
    'updated_at' => timestamp
  }
end

def create_poll(request_body:)
  json = JSON.parse(request_body)
  timestamp = unique_date
  poll = {
    'id' => json['id'] || unique_id,
    'name' => json['name'].to_s,
    'description' => json['description'].to_s,
    'options' => (json['options'] || []).map { |option| poll_option(option['text']) },
    'allow_answers' => json['allow_answers'] || false,
    'allow_user_suggested_options' => json['allow_user_suggested_options'] || false,
    'enforce_unique_vote' => json['enforce_unique_vote'] || false,
    'max_votes_allowed' => json['max_votes_allowed'],
    'voting_visibility' => json['voting_visibility'] || 'public',
    'is_closed' => json['is_closed'] || false,
    'created_by' => current_user,
    'created_by_id' => current_user['id'],
    'created_at' => timestamp,
    'updated_at' => timestamp,
    'vote_count' => 0,
    'answers_count' => 0,
    'own_votes' => [],
    'latest_answers' => [],
    'latest_votes_by_option' => {},
    'vote_counts_by_option' => {}
  }
  $polls << poll
  { poll: poll, duration: '7.11ms' }.to_s
end

def update_poll(request_body:)
  json = JSON.parse(request_body)
  poll = find_poll(json['id'])
  halt(400, { message: "poll #{json['id']} not found" }.to_s) unless poll

  %w[name description allow_answers allow_user_suggested_options enforce_unique_vote
     max_votes_allowed voting_visibility is_closed].each do |key|
    poll[key] = json[key] if json.key?(key)
  end
  if json['options']
    poll['options'] = json['options'].map do |option|
      existing = poll['options'].detect { |opt| opt['id'] == option['id'] }
      existing ? existing.merge('text' => option['text'].to_s) : poll_option(option['text'])
    end
  end
  poll['updated_at'] = unique_date
  broadcast_poll_event(type: PollEventType.updated, poll: poll)
  { poll: poll, duration: '7.11ms' }.to_s
end

def partial_update_poll(poll_id:, request_body:)
  json = JSON.parse(request_body)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  closing = json.dig('set', 'is_closed') && !poll['is_closed']
  (json['set'] || {}).each { |key, value| poll[key] = value }
  (json['unset'] || []).each { |key| poll[key] = nil }
  poll['updated_at'] = unique_date
  broadcast_poll_event(type: closing ? PollEventType.closed : PollEventType.updated, poll: poll)
  { poll: poll, duration: '7.11ms' }.to_s
end

def delete_poll(poll_id:)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  message = find_poll_message(poll_id)
  $polls.delete(poll)
  message['poll'] = nil if message
  broadcast_poll_event(type: PollEventType.deleted, poll: poll, message: message)
  { duration: '7.11ms' }.to_s
end

def create_poll_option(poll_id:, request_body:)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  option = poll_option(JSON.parse(request_body)['text'])
  poll['options'] << option
  poll['updated_at'] = unique_date
  broadcast_poll_event(type: PollEventType.updated, poll: poll)
  { poll_option: option, duration: '7.11ms' }.to_s
end

def update_poll_option(poll_id:, request_body:)
  json = JSON.parse(request_body)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  option = poll['options'].detect { |opt| opt['id'] == json['id'] }
  halt(400, { message: "option #{json['id']} not found" }.to_s) unless option

  option['text'] = json['text'].to_s
  poll['updated_at'] = unique_date
  broadcast_poll_event(type: PollEventType.updated, poll: poll)
  { poll_option: option, duration: '7.11ms' }.to_s
end

def delete_poll_option(poll_id:, option_id:)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  poll['options'].delete_if { |option| option['id'] == option_id }
  removed_votes = poll['latest_votes_by_option'].delete(option_id) || []
  poll['vote_counts_by_option'].delete(option_id)
  poll['vote_count'] -= removed_votes.count
  poll['own_votes'].delete_if { |vote| vote['option_id'] == option_id }
  poll['updated_at'] = unique_date
  broadcast_poll_event(type: PollEventType.updated, poll: poll)
  { duration: '7.11ms' }.to_s
end

def query_poll_votes(poll_id:, request_body:)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  json = request_body.empty? ? {} : JSON.parse(request_body)
  filter = json['filter'] || {}
  votes =
    if filter['is_answer']
      poll['latest_answers']
    elsif filter['option_id']
      poll['latest_votes_by_option'][filter['option_id']] || []
    else
      poll['latest_votes_by_option'].values.flatten + poll['latest_answers']
    end
  votes = votes.first(json['limit'].to_i) if json['limit']
  { votes: votes, duration: '7.11ms' }.to_s
end

def cast_poll_vote(message_id:, poll_id:, vote_data:, user: current_user)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  timestamp = unique_date
  if vote_data['answer_text']
    vote = poll_vote(poll_id: poll_id, option_id: '', user: user, timestamp: timestamp)
    vote['is_answer'] = true
    vote['answer_text'] = vote_data['answer_text']
    poll['latest_answers'].unshift(vote)
    poll['answers_count'] += 1
    event_type = PollEventType.vote_casted
  else
    option_id = vote_data['option_id']
    halt(400, { message: "option #{option_id} not found" }.to_s) unless poll['options'].any? { |opt| opt['id'] == option_id }

    previous_votes = poll['enforce_unique_vote'] ? remove_user_votes(poll: poll, user: user) : []
    vote = poll_vote(poll_id: poll_id, option_id: option_id, user: user, timestamp: timestamp)
    (poll['latest_votes_by_option'][option_id] ||= []) << vote
    poll['vote_counts_by_option'][option_id] = (poll['vote_counts_by_option'][option_id] || 0) + 1
    poll['vote_count'] += 1
    poll['own_votes'] << vote if user['id'] == current_user['id']
    event_type = previous_votes.any? ? PollEventType.vote_changed : PollEventType.vote_casted
  end

  poll['updated_at'] = timestamp
  broadcast_poll_event(
    type: event_type,
    poll: poll,
    poll_vote: vote,
    message: find_message_by_id(message_id)
  )
  { vote: vote, duration: '7.11ms' }.to_s
end

def remove_poll_vote(message_id:, poll_id:, vote_id:)
  poll = find_poll(poll_id)
  halt(400, { message: "poll #{poll_id} not found" }.to_s) unless poll

  vote = (poll['latest_votes_by_option'].values.flatten + poll['latest_answers'])
         .detect { |v| v['id'] == vote_id }
  halt(400, { message: "vote #{vote_id} not found" }.to_s) unless vote

  if vote['is_answer']
    poll['latest_answers'].delete(vote)
    poll['answers_count'] -= 1
  else
    option_votes = poll['latest_votes_by_option'][vote['option_id']]
    option_votes&.delete(vote)
    poll['vote_counts_by_option'][vote['option_id']] = [(poll['vote_counts_by_option'][vote['option_id']] || 1) - 1, 0].max
    poll['vote_count'] = [poll['vote_count'] - 1, 0].max
  end
  poll['own_votes'].delete_if { |own| own['id'] == vote_id }
  poll['updated_at'] = unique_date

  broadcast_poll_event(
    type: PollEventType.vote_removed,
    poll: poll,
    poll_vote: vote,
    message: find_message_by_id(message_id)
  )
  { vote: vote, duration: '7.11ms' }.to_s
end

# Drops every non-answer vote of `user`, used to model `enforce_unique_vote`:
# the backend replaces the previous vote and reports the cast as `poll.vote_changed`.
def remove_user_votes(poll:, user:)
  removed = []
  poll['latest_votes_by_option'].each do |option_id, votes|
    votes.delete_if do |vote|
      next false unless vote['user_id'] == user['id']

      removed << vote
      poll['vote_counts_by_option'][option_id] = [(poll['vote_counts_by_option'][option_id] || 1) - 1, 0].max
      poll['vote_count'] = [poll['vote_count'] - 1, 0].max
      true
    end
  end
  poll['own_votes'].delete_if { |vote| removed.any? { |removed_vote| removed_vote['id'] == vote['id'] } }
  removed
end

# Clients map every poll event through `cid`, which only exists once a message
# carries the poll, so the broadcast is skipped while the poll has no message.
def broadcast_poll_event(type:, poll:, poll_vote: nil, message: nil)
  message ||= find_poll_message(poll['id'])
  return unless message

  event = {
    'type' => type,
    'created_at' => unique_date,
    'cid' => message['cid'],
    'channel_type' => 'messaging',
    'channel_id' => message['channel_id'],
    'message_id' => message['id'],
    'poll' => poll
  }
  if poll_vote
    event['poll_vote'] = poll_vote
    event['user'] = poll_vote['user']
  end
  broadcast_event(event)
end
