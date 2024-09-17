def create_reaction(type:, message_id:, user: current_user, response: Mocks.reaction, delete: nil)
  timestamp = unique_date
  message = $message_list.detect { |msg| msg['id'] == message_id }

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
  response['created_at'] = timestamp
  response['cid'] = message['cid']
  response['channel_id'] = message['cid'].split(':').last
  response['type'] = delete ? 'reaction.deleted' : 'reaction.new'
  response['user'] = user
  response.to_s
end
