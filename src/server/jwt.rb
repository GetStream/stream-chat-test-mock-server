jwt = { expired_token_timeout: 0, server_error_timeout: 0, invalid_token_timeout: 0, invalid_token_date_timeout: 0, invalid_token_signature_timeout: 0 }

# This is an invalid token, no need to hack it :)
mocked_token = 'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoibHVrZV9za3l3YWxrZXIiLCJleHAiOjE2NjgwMTIzNTN9.UJ-LDHZFDP10sqpZU9bzPAChgersjDfqKjoi5Plg8qI'

get '/jwt/get' do
  time = Time.now.to_i
  if time < jwt[:server_error_timeout].to_i
    # Broken server flow
    halt(500, 'Intentional error')
  elsif time < jwt[:expired_token_timeout].to_i
    # Expired token flow
    $health_check = expired_jwt
    mocked_token
  elsif time < jwt[:invalid_token_timeout].to_i
    # Invalid token flow
    $health_check = invalid_jwt
    "invalid_#{mocked_token}"
  elsif time < jwt[:invalid_token_date_timeout].to_i
    # Invalid token date flow
    $health_check = invalid_jwt_date
    mocked_token
  elsif time < jwt[:invalid_token_signature_timeout].to_i
    # Invalid token date flow
    $health_check = invalid_jwt_signature
    mocked_token
  else
    # Valid token flow
    expiration_timeout = 5
    $health_check = Mocks.health_check.to_s
    Thread.new do
      sleep(expiration_timeout)
      $health_check = expired_jwt
    end
    mocked_token
  end
end

post '/jwt/revoke_token' do
  jwt[:expired_token_timeout] = Time.now.to_i + params['duration'].to_i
  halt(200)
end

post '/jwt/invalidate_token' do
  jwt[:invalid_token_timeout] = Time.now.to_i + params['duration'].to_i
  halt(200)
end

post '/jwt/invalidate_token_date' do
  jwt[:invalid_token_date_timeout] = Time.now.to_i + params['duration'].to_i
  halt(200)
end

post '/jwt/invalidate_token_signature' do
  jwt[:invalid_token_signature_timeout] = Time.now.to_i + params['duration'].to_i
  halt(200)
end

post '/jwt/break_token_generation' do
  jwt[:server_error_timeout] = Time.now.to_i + params['duration'].to_i
  halt(200)
end

def expired_jwt
  jwt_error(40)
end

def invalid_jwt
  jwt_error(41)
end

def invalid_jwt_date
  jwt_error(42)
end

def invalid_jwt_signature
  jwt_error(43)
end

def jwt_error(code)
  <<-JSON
  {"type":"connection.error","created_at":"2025-02-17T16:52:12.479337212Z","connection_id":"","error":{"code":#{code},"message":"JWTAuth error","StatusCode":401,"duration":"","more_info":"","details":[]}}
  JSON
end
