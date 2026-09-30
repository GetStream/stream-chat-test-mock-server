require 'puma'
require 'sinatra'
require 'socket'

set :port, ARGV[0] || 4567
FileUtils.mkdir_p('logs')

get '/start/:test_name' do
  start_mock_server(test_name: params[:test_name], port: params[:port], api_version: params[:api_version])
end

get '/stop' do
  Thread.new do
    sleep 1
    exit
  end
end

# `api_version=v2` serves the v2 fixtures; anything else keeps the v1 ones.
def start_mock_server(test_name:, port:, api_version:)
  port = available_port if port.to_s.empty?
  api_version = api_version == 'v2' ? 'v2' : 'v1'
  Thread.new do
    log_path = "logs/#{test_name}_#{Time.now.to_i}_#{port}.log"
    `bundle exec ruby src/server.rb #{port} #{api_version} > #{log_path} 2>&1 &`
    puts("Port: #{port}")
  end
  port.to_s
end

def available_port
  server = TCPServer.new(0)
  port = server.addr[1]
  server.close
  port
end
