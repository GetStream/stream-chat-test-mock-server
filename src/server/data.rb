# Sub-second precision, like the real backend. Clients drop read-state updates
# whose timestamp is not strictly newer than the last processed one, so two
# events stamped within the same second would lose one unread count.
def time_format
  @time_format ||= '%Y-%m-%dT%H:%M:%S.%6NZ'
end

def unique_date
  Time.now.utc.strftime(time_format)
end

def update_date(timestamp:, plus_seconds: nil, minus_seconds: nil)
  # Time.parse instead of Time.strptime(timestamp, time_format): template fixtures
  # still carry second-precision or nanosecond dates that do not match time_format.
  time = Time.parse(timestamp)
  if plus_seconds
    (time + plus_seconds).utc.strftime(time_format)
  elsif minus_seconds
    (time - minus_seconds).utc.strftime(time_format)
  else
    timestamp
  end
end

def unique_id
  SecureRandom.uuid
end

def test_asset(type)
  assets = {
    'image' => 'https://vignette.wikia.nocookie.net/starwars/images/2/20/LukeTLJ.jpg',
    'video' => 'https://raw.githubusercontent.com/GetStream/stream-chat-test-mock-server/main/src/assets/video.mp4',
    'file' => 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
  }
  assets[type]
end

# The real backend answers uploads with the asset URL, the request duration and,
# only when a thumbnail was generated, a `thumb_url`. Clients parse `duration` as
# non-null, so it has to be there on every upload response.
def upload_response(type)
  { file: test_asset(type), duration: '49.41ms' }
end

# Uploads are multipart, so the request content type is always `multipart/form-data`;
# the media type of the upload is on the `file` part itself.
def uploaded_file_type
  part = params['file']
  mime_type = part.is_a?(Hash) ? part['type'].to_s : request.content_type.to_s
  mime_type.include?('video') ? 'video' : 'file'
end
