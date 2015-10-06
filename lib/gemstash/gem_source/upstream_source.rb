require "gemstash"
require "cgi"

module Gemstash
  module GemSource
    # GemSource that purely redirects to the upstream server.
    class RedirectSource < Gemstash::GemSource::Base
      def self.rack_env_rewriter
        @rack_env_rewriter ||= Gemstash::GemSource::RackEnvRewriter.new(%r{\A/redirect/([^/]+)})
      end

      def self.matches?(env)
        rewriter = rack_env_rewriter.for(env)
        return false unless rewriter.matches?
        rewriter.rewrite
        env["gemstash.upstream"] = rewriter.upstream_url
        true
      end

      def serve_root
        cache_control :public, :max_age => 31_536_000
        redirect upstream.url(nil, request.query_string)
      end

      def serve_add_gem
        halt 403, "Cannot add gem to an upstream server!"
      end

      def serve_yank
        halt 403, "Cannot yank from an upstream server!"
      end

      def serve_unyank
        halt 403, "Cannot unyank from an upstream server!"
      end

      def serve_add_spec_json
        halt 403, "Cannot add spec to an upstream server!"
      end

      def serve_remove_spec_json
        halt 403, "Cannot remove spec from an upstream server!"
      end

      def serve_dependencies
        redirect upstream.url("/api/v1/dependencies", request.query_string)
      end

      def serve_dependencies_json
        redirect upstream.url("/api/v1/dependencies.json", request.query_string)
      end

      def serve_names
        redirect upstream.url("/names", request.query_string)
      end

      def serve_versions
        redirect upstream.url("/versions", request.query_string)
      end

      def serve_info(name)
        redirect upstream.url("/info/#{name}", request.query_string)
      end

      def serve_marshal(id)
        redirect upstream.url("/quick/Marshal.4.8/#{id}", request.query_string)
      end

      def serve_actual_gem(id)
        redirect upstream.url("/fetch/actual/gem/#{id}", request.query_string)
      end

      def serve_gem(id)
        redirect upstream.url("/gems/#{id}", request.query_string)
      end

      def serve_latest_specs
        redirect upstream.url("/latest_specs.4.8.gz", request.query_string)
      end

      def serve_specs
        redirect upstream.url("/specs.4.8.gz", request.query_string)
      end

      def serve_prerelease_specs
        redirect upstream.url("/prerelease_specs.4.8.gz", request.query_string)
      end

    private

      def web_helper
        @web_helper ||= Gemstash::WebHelper.new(
          http_client: @app.http_client_for(upstream.to_s),
          server_url: upstream.to_s)
      end

      def upstream
        Gemstash::Upstream.new(env["gemstash.upstream"])
      end
    end

    # GemSource for gems in an upstream server.
    class UpstreamSource < Gemstash::GemSource::RedirectSource
      include Gemstash::GemSource::DependencyCaching
      include Gemstash::Env::Helper

      def self.rack_env_rewriter
        @rack_env_rewriter ||= Gemstash::GemSource::RackEnvRewriter.new(%r{\A/upstream/([^/]+)})
      end

      def serve_gem(id)
        gem = fetch_gem(id)
        headers.update(gem.properties)
        gem.content
      rescue Gemstash::WebError => e
        halt e.code
      end

    private

      def dependencies
        @dependencies ||= Gemstash::Dependencies.for_upstream(web_helper)
      end

      def storage
        @storage ||= Gemstash::Storage.new(gemstash_env.base_file("gem_cache"))
      end

      def fetch_gem(id)
        gem = storage.resource(id)
        if gem.exist?
          fetch_local_gem(gem)
        else
          fetch_remote_gem(gem)
        end
      end

      def fetch_local_gem(gem)
        log.info "Gem #{gem.name} exists, returning cached"
        gem.load
      end

      def fetch_remote_gem(gem)
        log.info "Gem #{gem.name} is not cached, fetching"
        web_helper.get("/gems/#{gem.name}") do |body, headers|
          gem.save(body, properties: headers)
        end
      end
    end

    # GemSource for https://rubygems.org (specifically when defined by using the
    # default upstream).
    class RubygemsSource < Gemstash::GemSource::UpstreamSource
      def self.matches?(env)
        env["gemstash.upstream"] = env["gemstash.env"].config[:rubygems_url]
        true
      end
    end
  end
end