require 'puma'
require 'sinatra'
require 'socket'

set :port, ARGV[0] || 4567
FileUtils.mkdir_p('logs')

get '/start' do
  start_mock_server(params[:port])
end

get '/stop' do
  stop_mock_server(params[:port]) unless params[:port].to_s.empty?
end

get '/clean' do
  clean
end

def clean
  Dir.glob('logs/*').each do |file|
    port = file.scan(/\d+/).join.to_i
    stop_mock_server(port)
    FileUtils.rm_f(file)
  end
  'OK'
end

def start_mock_server(port)
  port = available_port if port.to_s.empty?
  Thread.new { `bundle exec ruby mock_server.rb #{port} > logs/#{port}.log 2>&1 &` }
  port.to_s
end

def stop_mock_server(port)
  `lsof -t -i:#{port} | xargs kill -9`
  'OK'
end

def available_port
  server = TCPServer.new(0)
  port = server.addr[1]
  server.close
  port
end
