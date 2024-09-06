def time_format
  @time_format ||= '%Y-%m-%dT%H:%M:%SZ'
end

def unique_date
  Time.now.utc.strftime(time_format)
end

def update_date(timestamp:, plus_seconds:)
  time = Time.strptime(timestamp, time_format)
  (time + plus_seconds).utc.strftime(time_format)
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
