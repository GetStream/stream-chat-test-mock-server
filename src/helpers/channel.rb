def find_channel_by_id(id)
  $channel_list['channels'].detect { |channel| channel['channel']['id'] == id }
end
