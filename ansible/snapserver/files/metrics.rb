#!/usr/bin/env ruby

require "net/http"
require "uri"
require "json"

class Metrics
  def self.call
    fetch_clients.each { |client| report_client(client) }
  end

  def self.fetch_clients
    uri = URI("http://192.168.1.94:1780/jsonrpc")
    data = {id: 0, jsonrpc: "2.0", method: "Server.GetStatus"}.to_json
    resp = Net::HTTP.post(uri, data)

    json_response = JSON.parse(resp.body)
    json_response
      .dig("result", "server", "groups")
      .flat_map { |r| r["clients"] }
  end

  def self.report_client(client)
    job = "snapclient"
    instance = client["id"]
    uri = URI("http://192.168.1.94:9091/metrics/job/#{job}/instance/#{instance}")

    labels = "{hostname=\"#{client.dig("host", "name")}\"}"

    body = <<~BODY
      snapclient_connected#{labels} #{(client["connected"] == "true") ? 1 : 0}
      snapclient_last_seen#{labels} #{client.dig("lastSeen", "sec")}
    BODY

    resp = Net::HTTP.post(uri, body)

    puts body
    puts "push response code: #{resp.code} #{resp.body}"

    pp client
  end
end

Metrics.call
