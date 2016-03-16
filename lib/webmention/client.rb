require 'pry'

module Webmention
  class Client
    # Public: Returns a URI of the url initialized with.
    attr_reader :url

    # Public: Returns an array of links contained within the url.
    attr_reader :links

    # Public: Create a new client
    #
    # url - The url you want us to crawl.
    def initialize(url)
      @url = URI.parse(url)
      @links ||= Set.new

      unless Webmention::Client.valid_http_url? @url
        raise ArgumentError.new "#{@url} is not a valid HTTP or HTTPS URI."
      end
    end

    # Public: Crawl the url this client was initialized with.
    #
    # Returns the number of links found.
    def crawl
      source = JSON.parse(open(self.url).read)
      @links = source["supplement"]["within"]
      
      return @links.count
=begin
      @links ||= Set.new
      if @url.nil?
        raise ArgumentError.new "url is nil."
      end

      Nokogiri::HTML(open(self.url)).css('.h-entry a').each do |link|
        link = link.attribute('href').to_s
        if Webmention::Client.valid_http_url? link
          @links.add link
        end
      end

      return @links.count
=end
    end

    # Public: Sends mentions to each of the links found in the page.
    #
    # Returns the number of links mentioned.
    def send_mentions
      if self.links.nil? or self.links.empty?
        self.crawl
      end

      cnt = 0
      self.links.each do |link|
        endpoint = Webmention::Client.supports_webmention? link
        if endpoint
          cnt += 1 if Webmention::Client.send_mention endpoint, self.url, link
        end
      end

      return cnt
    end

    # Public: Send a mention to an endoint about a link from a link.
    #
    # endpoint - URL to send mention to.
    # source - Source of mention (your page).
    # target - The link that was mentioned in the source page.
    #
    # Returns a boolean.
    def self.send_mention endpoint, source, target, full_response=false
      data = {
        :source => source,
        :target => target,
      }

      begin
        response = HTTParty.post(endpoint, {
          :body => data
        })

        if full_response
          return response
        else
          return response.code == 200 || response.code == 202
        end
      rescue
        return false
      end
    end

    # Public: Fetch a url and check if it supports webmention
    #
    # url - URL to check
    #
    # Returns false if does not support webmention, returns string
    # of url to ping if it does.
    def self.supports_webmention? url

      return false if !Webmention::Client.valid_http_url? url
      
      manifest = JSON.parse(open(url).read).to_hash
      
      services = manifest["service"]
      
      #test if manifest has webmention listening service
      if services.class == Hash ## ??
        if services["profile"] == "http://w3.org/TR/webmention"
            webmention_receiver = service["@id"]
        end
      else
        services.each do |service|
          if service.class == Hash
            if service["profile"] == "http://w3.org/TR/webmention"
              webmention_receiver = service["@id"]
            end
          end
        end
        return webmention_receiver
      end
      
=begin
      doc = nil

      begin
        response = HTTParty.get(url, {
          :timeout => 3,
          :headers => {
            'User-Agent' => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.57 Safari/537.36 (https://rubygems.org/gems/webmention)",
            'Accept' => '*/*'
          }
        })

        # First check the HTTP Headers
        if !response.headers['Link'].nil? 
          endpoint = self.discover_webmention_endpoint_from_header response.headers['Link']
          return endpoint if endpoint
        end

        # Do we support webmention?
        endpoint = self.discover_webmention_endpoint_from_html response.body.to_s
        return endpoint if endpoint

        # TODO: Move to supports_pingback? method
        # Last chance, do we support Pingback?
        # if !doc.css('link[rel="pingback"]').empty?
        #   return doc.css('link[rel="pingback"]').attribute("href").value
        # end

      rescue EOFError
      rescue Errno::ECONNRESET
      end

      return false
=end      
    end

    def self.discover_webmention_endpoint_from_html html
      doc = Nokogiri::HTML(html)
      if !doc.css('[rel="webmention"]').empty?
        doc.css('[rel="webmention"]').attribute("href").value
      elsif !doc.css('[rel="http://webmention.org/"]').empty?
        doc.css('[rel="http://webmention.org/"]').attribute("href").value
      elsif !doc.css('[rel="http://webmention.org"]').empty?
        doc.css('[rel="http://webmention.org"]').attribute("href").value
      else
        false
      end
    end

    def self.discover_webmention_endpoint_from_header header
      if matches = header.match(%r{<(https?://[^>]+)>; rel="webmention"})
        return matches[1]
      elsif matches = header.match(%r{rel="webmention"; <(https?://[^>]+)>})
        return matches[1]
      elsif matches = header.match(%r{<(https?://[^>]+)>; rel="http://webmention\.org/?"})
        return matches[1]
      elsif matches = header.match(%r{rel="http://webmention\.org/?"; <(https?://[^>]+)>})
        return matches[1]
      end
      return false
    end

    # Public: Use URI to parse a url and check if it is HTTP or HTTPS.
    #
    # url - URL to check
    #
    # Returns a boolean.
    def self.valid_http_url? url
      if url.is_a? String
        url = URI.parse(url)
      end

      return (url.is_a? URI::HTTP or url.is_a? URI::HTTPS)
    end
  end
end
