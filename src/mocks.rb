class Mocks
  def self.health_check
    JSON.parse(File.read('src/jsons/ws_health_check.json'))
  end

  def self.channels
    JSON.parse(File.read('src/jsons/http_channels.json'))
  end

  def self.event
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

  def self.attachment
    JSON.parse(File.read('src/jsons/http_attachment.json'))
  end

  def self.youtube_link
    JSON.parse(File.read('src/jsons/http_youtube_link.json'))
  end

  def self.unsplash_link
    JSON.parse(File.read('src/jsons/http_unsplash_link.json'))
  end
end
