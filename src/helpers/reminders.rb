# Message reminders for the app user, kept in $reminders. The message itself also
# carries a `reminder` info object so message list responses reflect the state.

def find_reminder(message_id)
  $reminders.detect { |reminder| reminder['message_id'] == message_id }
end

def create_reminder(message_id:, remind_at:)
  message = find_message_by_id(message_id)
  halt(400, { message: "message #{message_id} not found" }.to_s) unless message

  timestamp = unique_date
  reminder = {
    'channel_cid' => message['cid'],
    'message_id' => message_id,
    'user_id' => current_user['id'],
    'created_at' => timestamp,
    'updated_at' => timestamp,
    'remind_at' => remind_at,
    'message' => message
  }
  message['reminder'] = reminder_info(reminder)
  $reminders << reminder
  { reminder: reminder, duration: '7.11ms' }.to_s
end

def update_reminder(message_id:, remind_at:)
  reminder = find_reminder(message_id)
  halt(400, { message: "reminder for message #{message_id} not found" }.to_s) unless reminder

  reminder['remind_at'] = remind_at
  reminder['updated_at'] = unique_date
  reminder['message']['reminder'] = reminder_info(reminder)
  { reminder: reminder, duration: '7.11ms' }.to_s
end

def delete_reminder(message_id:)
  message = find_message_by_id(message_id)
  message['reminder'] = nil if message
  $reminders.delete_if { |reminder| reminder['message_id'] == message_id }
  { duration: '7.11ms' }.to_s
end

# The `reminder` object embedded in a message has no `message` inside (that would
# be a circular reference when serializing).
def reminder_info(reminder)
  reminder.reject { |key, _| key == 'message' }
end
