# The real v2 API sends every timestamp as unix nanoseconds, and stream-chat-js v10 reads them only in
# that form. The server keeps building and storing ISO 8601 strings (`unique_date`, `update_date`), so a
# run started with `ns` converts at the boundary: date strings become integers in every response and
# websocket frame, and integer dates in a request become strings again before a handler reads them.

ISO_DATE = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})\z/
# Below this an integer is not a nanosecond timestamp (1e18 ns is September 2001).
MIN_NS_TIMESTAMP = 1_000_000_000_000_000_000
DATE_KEYS = %w[last_read last_active pin_expires expires ban_expires].freeze

def date_key?(key)
  key = key.to_s
  key.end_with?('_at') || DATE_KEYS.include?(key)
end

def iso_to_ns(value)
  time = Time.iso8601(value)
  (time.to_i * 1_000_000_000) + time.nsec
rescue ArgumentError
  value
end

def ns_to_iso(value)
  Time.at(value / 1_000_000_000, value % 1_000_000_000, :nsec).utc.strftime(time_format)
end

# Date strings under a date key become nanosecond integers.
def to_ns_timestamps(value)
  case value
  when Array
    value.map { |child| to_ns_timestamps(child) }
  when Hash
    value.to_h do |key, child|
      [key, child.kind_of?(String) && date_key?(key) && child.match?(ISO_DATE) ? iso_to_ns(child) : to_ns_timestamps(child)]
    end
  else
    value
  end
end

# Nanosecond integers under a date key become the server's date strings.
def from_ns_timestamps(value)
  case value
  when Array
    value.map { |child| from_ns_timestamps(child) }
  when Hash
    value.to_h do |key, child|
      [key, child.kind_of?(Integer) && date_key?(key) && child >= MIN_NS_TIMESTAMP ? ns_to_iso(child) : from_ns_timestamps(child)]
    end
  else
    value
  end
end

# A websocket frame in the run's timestamp encoding. Frames that are not JSON objects pass unchanged.
def encode_ws_frame(data)
  return data unless $ns_timestamps

  json = JSON.parse(data.to_s)
  json.kind_of?(Hash) ? to_ns_timestamps(json).to_s : data
rescue JSON::ParserError
  data
end
