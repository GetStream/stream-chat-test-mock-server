class Mocks
  # The user sync.rb passes to add_members when recording http_add_member.json.
  MEMBER_USER_ID = 'leia_organa'.freeze

  def self.health_check
    JSON.parse(File.read('src/jsons/ws_health_check.json'))
  end

  def self.channels
    JSON.parse(File.read('src/jsons/http_channels.json'))
  end

  def self.ws_channel_update
    JSON.parse(File.read('src/jsons/ws_events_channel.json'))
  end

  def self.event
    JSON.parse(File.read('src/jsons/http_events.json'))
  end

  def self.event_ws
    JSON.parse(File.read('src/jsons/ws_events.json'))
  end

  def self.message
    JSON.parse(File.read('src/jsons/http_message.json'))
  end

  def self.message_ws
    JSON.parse(File.read('src/jsons/ws_message.json'))
  end

  def self.giphy
    JSON.parse(File.read('src/jsons/http_message_ephemeral.json'))
  end

  def self.reaction
    JSON.parse(File.read('src/jsons/http_reaction.json'))
  end

  def self.reaction_ws
    JSON.parse(File.read('src/jsons/ws_reaction.json'))
  end

  def self.youtube_link
    JSON.parse(File.read('src/jsons/http_youtube_link.json'))
  end

  def self.unsplash_link
    JSON.parse(File.read('src/jsons/http_unsplash_link.json'))
  end

  def self.giphy_link
    JSON.parse(File.read('src/jsons/http_giphy_link.json'))
  end

  def self.truncate
    JSON.parse(File.read('src/jsons/http_truncate.json'))
  end

  def self.member
    update_member['members'].detect { |member| member['user_id'] == MEMBER_USER_ID } ||
      raise("no #{MEMBER_USER_ID} in http_add_member.json; sync.rb records the add-member call for that user")
  end

  def self.update_member
    JSON.parse(File.read('src/jsons/http_add_member.json'))
  end

  def self.ws_update_member
    JSON.parse(File.read('src/jsons/ws_events_member.json'))
  end

  def self.draft
    JSON.parse(File.read('src/jsons/http_draft.json'))
  end

  def self.ws_draft_updated
    JSON.parse(File.read('src/jsons/ws_draft_updated.json'))
  end

  def self.ws_draft_deleted
    JSON.parse(File.read('src/jsons/ws_draft_deleted.json'))
  end
end
