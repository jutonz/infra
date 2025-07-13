#!/usr/bin/env ruby

require "net/http"
require "uri"
require "json"

class Metrics
  SNAPSERVER_HOST = "http://192.168.1.94:1780"
  PUSHGATEWAY_HOST = "http://192.168.1.94:9091"

  def self.call
    fetch_clients
      .map { |client| Thread.new { report_client(client) } }
      .each(&:join)
  end

  def self.fetch_clients
    uri = URI("#{SNAPSERVER_HOST}/jsonrpc")
    data = {id: 0, jsonrpc: "2.0", method: "Server.GetStatus"}.to_json
    resp = Net::HTTP.post(uri, data)

    json_response = JSON.parse(resp.body)
    json_response
      .dig("result", "server", "groups")
      .flat_map { |r| r["clients"] }
  end

  JOB = "snapclient"
  def self.report_client(client)
    instance = client["id"]
    uri = URI("#{PUSHGATEWAY_HOST}/metrics/job/#{JOB}/instance/#{instance}")

    labels = format_labels({
      hostname: client.dig("host", "name"),
      ip: client.dig("host", "ip")
    })

    body = <<~BODY
      snapclient_connected#{labels} #{(client["connected"] == "true") ? 1 : 0}
      snapclient_last_seen#{labels} #{client.dig("lastSeen", "sec")}
    BODY

    resp = Net::HTTP.post(uri, body)

    puts body
    puts "push response code: #{resp.code} #{resp.body}"

    pp client
  end

  def self.format_labels(labels_hash)
    pairs = labels_hash.map { |k, v| "#{k}=\"#{v}\"" }
    "{#{pairs.join(",")}}"
  end
end

Metrics.call
