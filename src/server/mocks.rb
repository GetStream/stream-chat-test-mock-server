class Mocks
  # The user sync.rb passes to add_members when recording http_add_member.json.
  MEMBER_USER_ID = 'leia_organa'.freeze

  def self.fixture(filename)
    directory = $api_version == :v2 ? 'src/jsons/v2' : 'src/jsons'
    JSON.parse(File.read("#{directory}/#{filename}"))
  end

  def self.health_check
    fixture('ws_health_check.json')
  end

  def self.channels
    fixture('http_channels.json')
  end

  def self.ws_channel_update
    fixture('ws_events_channel.json')
  end

  def self.event
    fixture('http_events.json')
  end

  def self.event_ws
    fixture('ws_events.json')
  end

  def self.message
    fixture('http_message.json')
  end

  def self.message_ws
    fixture('ws_message.json')
  end

  def self.giphy
    fixture('http_message_ephemeral.json')
  end

  def self.reaction
    fixture('http_reaction.json')
  end

  def self.reaction_ws
    fixture('ws_reaction.json')
  end

  def self.youtube_link
    fixture('http_youtube_link.json')
  end

  def self.unsplash_link
    fixture('http_unsplash_link.json')
  end

  def self.giphy_link
    fixture('http_giphy_link.json')
  end

  def self.truncate
    fixture('http_truncate.json')
  end

  def self.member
    update_member['members'].detect { |member| member['user_id'] == MEMBER_USER_ID } ||
      raise("no #{MEMBER_USER_ID} in http_add_member.json; sync.rb records the add-member call for that user")
  end

  def self.update_member
    fixture('http_add_member.json')
  end

  def self.ws_update_member
    fixture('ws_events_member.json')
  end

  def self.draft
    fixture('http_draft.json')
  end

  def self.ws_draft_updated
    fixture('ws_draft_updated.json')
  end

  def self.ws_draft_deleted
    fixture('ws_draft_deleted.json')
  end
end
