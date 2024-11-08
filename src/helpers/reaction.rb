class ReactionType
  def self.new
    'reaction.new'
  end

  def self.deleted
    'reaction.deleted'
  end
end

def send_reaction_ws(response:, event_type:)
  ws_response = Mocks.reaction_ws
  ws_response['message'] = response['message']
  ws_response['user'] = response['reaction']['user']
  ws_response['cid'] = response['message']['cid']
  ws_response['channel_id'] = response['message']['cid'].split(':').last
  ws_response['created_at'] = response['reaction']['created_at']
  ws_response['type'] = event_type
  $ws&.send(ws_response.to_s)
end

def create_reaction(type:, message_id:, user: current_user, delete: nil)
  timestamp = unique_date
  message = find_message_by_id(message_id)

  response = Mocks.reaction
  response['reaction']['type'] = type
  response['reaction']['user'] = user
  response['reaction']['user_id'] = user['id']
  response['reaction']['message_id'] = message_id
  response['reaction']['created_at'] = timestamp
  response['reaction']['updated_at'] = timestamp

  type_exists = message['reaction_scores'][type]
  if delete && type_exists
    if message['reaction_scores'][type] > 1
      message['reaction_scores'][type] -= 1
      message['reaction_counts'][type] -= 1
      message['reaction_groups'][type]['count'] -= 1
      message['reaction_groups'][type]['sum_scores'] -= 1
      message['reaction_groups'][type]['last_reaction_at'] = message['reaction_groups'][type]['first_reaction_at']
    else
      message['reaction_scores'].delete(type)
      message['reaction_counts'].delete(type)
      message['reaction_groups'].delete(type)
    end
    message['latest_reactions'].delete_if { |reaction| reaction['type'] == type && reaction['user_id'] == user['id'] }
  elsif type_exists
    message['reaction_scores'][type] += 1
    message['reaction_counts'][type] += 1
    message['reaction_groups'][type]['count'] += 1
    message['reaction_groups'][type]['sum_scores'] += 1
    message['latest_reactions'] << response['reaction']
  else
    message['reaction_scores'][type] = 1
    message['reaction_counts'][type] = 1
    message['reaction_groups'] ||= {}
    message['reaction_groups'][type] = {}
    message['reaction_groups'][type] = { count: 1, sum_scores: 1, first_reaction_at: timestamp, last_reaction_at: timestamp }
    message['latest_reactions'] << response['reaction']
  end

  response['message'] = message
  event_type = delete ? ReactionType.deleted : ReactionType.new

  send_reaction_ws(response: response, event_type: event_type)
  response.to_s
end
