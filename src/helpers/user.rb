def current_user
  return @user if @user

  @user = Mocks.message['message']['user']
  @user
end
