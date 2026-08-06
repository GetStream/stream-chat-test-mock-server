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
    'video' => 'https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4',
    'file' => 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
  }
  assets[type]
end
