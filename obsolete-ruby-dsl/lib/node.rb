# Copyright 2024 Kulpreet Singh
#
# This file is part of Bitcoin-DSL
#
# Bitcoin-DSL is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Bitcoin-DSL is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Bitcoin-DSL. If not, see <https://www.gnu.org/licenses/>.

# frozen_string_literal: true

require 'net/http'
require 'json'

DIR = '/tmp/x'
CHAIN = :regtest
RPCUSER = :test
RPCPASS = :test

def start_node
  command = "mkdir -p #{DIR} && \
             bitcoind -datadir=#{DIR} -chain=#{CHAIN} \
             -rpcuser=#{RPCUSER} -rpcpassword=#{RPCPASS} -daemonwait -txindex -debug=1"
  puts command
  system command
end

# We simply kill the process and remove the directory as we don't
# intend to preserve the database.
def stop_node
  pid_file = "#{DIR}/regtest/bitcoind.pid"
  return unless File.exist? pid_file

  pid = File.read pid_file
  if pid
    pid = pid.strip!.to_i
    Process.kill :KILL, pid if Process.getpgid(pid)
  end
  FileUtils.rm_r DIR
end

def node(command, *params)
  case command
  when :start
    start_node
  when :stop
    stop_node
  when :reset
    stop_node
    start_node
  else
    run_rpc_command(command, *params)
  end
end

def run_rpc_command(command, *params)
  config = Bitcoin::Node::Configuration.new(network: CHAIN)
  # logger.debug "Sending command '#{command}' with params #{params}"
  begin
    http, request = build_request command, config, *params
    response = http.request(request)
    parse_body(response.body)
  rescue StandardError => e
    puts e.message
  end
end

# Build request from passed in params. Params contains a single hash,
# and we only need the values. They keys are only useful to make the
# DSL easier to read.
def build_request(command, config, *params)
  query_params = !params.empty? ? params[0].values : []
  data = { method: command, params: query_params, id: 'jsonrpc' }
  uri = URI.parse(config.server_url)
  http = Net::HTTP.new(uri.hostname, uri.port)
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
