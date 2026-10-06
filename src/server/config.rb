post '/config/read_events' do
  $channel_list['channels'].each do |channel|
    channel['channel']['config']['read_events'] = params[:value].to_s.casecmp('true').zero?
  end
  halt(200)
end

post '/config/cooldown' do
  channel = find_channel_by_id($current_channel_id)

  if params[:enabled].to_s.casecmp('true').zero?
    channel['channel']['cooldown'] = params[:duration].to_i
    channel['channel']['own_capabilities'].delete('skip-slow-mode')
    channel['channel']['own_capabilities'] |= ['slow-mode']
  else
    channel['channel']['cooldown'] = nil
    channel['channel']['own_capabilities'].delete('slow-mode')
  end

  halt(200)
end

# Toggles message reminders (`user_message_reminders`) in the config of every channel.
post '/config/reminders' do
  $channel_list['channels'].each do |channel|
    channel['channel']['config']['user_message_reminders'] = params[:value].to_s.casecmp('true').zero?
  end
  halt(200)
end

# By default `id_around` returns the target message plus the next `limit` messages.
# Enabling this centres the window on the target like the real backend, so clients
# know there are older messages to load after jumping to a mid-page message.
post '/config/centered_around_pagination' do
  $centered_around_pagination = params[:value].to_s.casecmp('true').zero?
  halt(200)
end
