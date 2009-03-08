#!/usr/bin/env ruby

require "tempfile"
require "rubygems"
require "net/scp"
require "dl/import"

HOSTNAME = ENV["PUBLISH_HOSTNAME"]
USERNAME = ENV["PUBLISH_USERNAME"]
PASSWORD = ENV["PUBLISH_PASSWORD"]
FILENAME = ENV["PUBLISH_FILENAME"]

module Alarm
  extend DL::Importable
  dlload "libc.so.6"
  extern "unsigned int alarm(unsigned int)"
end

trap("ALRM") { exit 1 }
Alarm.alarm(5)

tempfile = Tempfile.new("publish")
tempfile.write($stdin.read)
tempfile.close

ssh = Net::SSH.start(HOSTNAME, USERNAME, :password => PASSWORD)
ssh.scp.upload!(tempfile.path, FILENAME)
ssh.close
exit 0

