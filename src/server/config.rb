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
  else
    channel['channel']['cooldown'] = nil
  end

  halt(200)
end
