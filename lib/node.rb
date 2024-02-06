# frozen_string_literal: true

require 'net/http'
require 'json'

DIR = '/tmp/x'
CHAIN = :regtest
RPCUSER = :test
RPCPASS = :test

def print_result(result)
  puts JSON.pretty_generate result
end

def start_node
  command = "mkdir -p #{DIR} && \
             bitcoind -datadir=#{DIR} -chain=#{CHAIN} -rpcuser=#{RPCUSER} -rpcpassword=#{RPCPASS} -daemonwait"
  puts command
  system command
end

def stop_node
  system "kill -9 `cat #{DIR}/regtest/bitcoind.pid` && rm -rf #{DIR}"
end

def node(command, *params)
  case command
  when :start
    start_node
  when :stop
    stop_node
  else
    run_rpc_command(command, *params)
  end
end

def run_rpc_command(command, *params)
  config = Bitcoin::Node::Configuration.new(network: CHAIN)
  puts "Sending command '#{command}' with params #{params}"
  begin
    http, request = build_request command, config, *params
    response = http.request(request)
    parse_body(response.body)
  rescue StandardError => e
    puts e.message
  end
end

def build_request(command, config, *params)
  data = { method: command, params: params, id: 'jsonrpc' }
  uri = URI.parse(config.server_url)
  http = Net::HTTP.new(uri.hostname, uri.port)
  http.use_ssl = false
  request = Net::HTTP::Post.new('/')
  request.basic_auth(RPCUSER, RPCPASS)
  request.content_type = 'application/json'
  request.body = data.to_json
  [http, request]
end

def parse_body(body)
  JSON.parse(body.to_str)['result']
rescue StandardError
  puts body.to_str
end
