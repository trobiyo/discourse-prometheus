# frozen_string_literal: true

require 'ipaddr'

module DiscoursePrometheus
  module Middleware; end
  class Middleware::Metrics

    def initialize(app, settings = {})
      @app = app
    end

    def call(env)
      STDERR.puts "call(env)"
      if intercept?(env)
        STDERR.puts "intercept?(env)"
        metrics(env)
      else
        STDERR.puts "app.call(env)"
        @app.call(env)
      end
    end

    private

    PRIVATE_IP = /^(127\.)|(192\.168\.)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(::1$)|([fF][cCdD])/

    def is_private_ip?(env)
      request = Rack::Request.new(env)
      ip = IPAddr.new(request.ip) rescue nil
      STDERR.puts "is_private_ip? ip: #{ip.to_s}"
      !!(ip && ip.to_s =~ PRIVATE_IP)
    end

    def is_trusted_ip?(env)
      return false if GlobalSetting.prometheus_trusted_ip_whitelist_regex.empty?
      begin
        trusted_ip_regex = Regexp.new GlobalSetting.prometheus_trusted_ip_whitelist_regex
        request = Rack::Request.new(env)
        ip = IPAddr.new(request.ip)
      rescue => e
        # failed to parse regex
        Discourse.warn_exception(e, message: "Error parsing prometheus trusted ip whitelist", env: env)
      end
      STDERR.puts "is_trusted_ip? trusted_ip_regex: #{trusted_ip_regex} | ip: #{ip.to_s}"
      !!(trusted_ip_regex && ip && ip.to_s =~ trusted_ip_regex)
    end

    def is_admin?(env)
      host = RailsMultisite::ConnectionManagement.host(env)
      result = false
      RailsMultisite::ConnectionManagement.with_hostname(host) do
        result = RailsMultisite::ConnectionManagement.current_db == "default"
        result &&= !!CurrentUser.lookup_from_env(env)&.admin
      end
      result
    end

    def intercept?(env)
      if env["PATH_INFO"] == "/metrics"        
        is_private_ip = is_private_ip?(env)
        is_trusted_ip = is_trusted_ip?(env)
        is_admin = is_admin?(env)
        STDERR.puts "intercept? is_private_ip?(env): #{is_private_ip.to_s} | is_trusted_ip?(env): #{is_trusted_ip.to_s} | is_admin?(env): #{is_admin.to_s}"
        return is_private_ip?(env) || is_trusted_ip?(env) || is_admin?(env)
      end
      false
    end

    def metrics(env)
      data = Net::HTTP.get(URI("http://localhost:#{GlobalSetting.prometheus_collector_port}/metrics"))
      [200, {
         "Content-Type" => "text/plain; charset=utf-8",
         "Content-Length" => data.bytesize.to_s
       }, [data]]
    end

  end
end
