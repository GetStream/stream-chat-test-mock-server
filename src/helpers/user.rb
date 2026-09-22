def current_user
  return @user if @user

  @user = Mocks.message['message']['user']
  @user
end

# The v2 auth frame is the only text frame the client sends. The token is not validated:
# the token-failure flows are driven by /jwt/* instead.
def websocket_auth_frame?(data)
  frame = JSON.parse(data.to_s)
  frame.kind_of?(Hash) && frame.key?('token')
rescue JSON::ParserError
  false
end

GUEST_TOKEN = 'dummy-guest-token'.freeze

def create_guest_user(request_user:, nested_custom:)
  timestamp = unique_date
  extra = request_user['custom'] || request_user.reject { |key, _| %w[id name image custom].include?(key) }
  user = {
    'id' => request_user['id'],
    'role' => 'guest',
    'name' => request_user['name'],
    'image' => request_user['image'],
    'created_at' => timestamp,
    'updated_at' => timestamp,
    'last_active' => timestamp,
    'banned' => false,
    'online' => false,
    'invisible' => false,
    'shadow_banned' => false,
    'language' => '',
    'teams' => [],
    'blocked_user_ids' => []
  }
  user = nested_custom ? user.merge('custom' => extra) : user.merge(extra)
  { user: user, access_token: GUEST_TOKEN, duration: '7.11ms' }.to_s
end
