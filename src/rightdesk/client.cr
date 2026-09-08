require "http/client"
require "json"
require "uri"
require "./config"
require "./auth"

module RightDesk
  # Thin HTTP wrapper: injects the Bearer token, targets BASE_URL, returns a
  # tiny Response the commands can branch on. Kept minimal on purpose — the
  # commands own their own JSON shaping/output.
  module Client
    record Response, status : Int32, body : String do
      def success? : Bool
        status >= 200 && status < 300
      end
    end

    # `query` is an already-encoded query string (e.g. from `URI::Params.build`).
    def self.get(path : String, query : String? = nil) : Response
      request("GET", path, query: query)
    end

    def self.post(path : String, body : String? = nil) : Response
      request("POST", path, body: body)
    end

    private def self.request(method : String, path : String,
                             query : String? = nil, body : String? = nil) : Response
      uri = URI.parse("#{RightDesk::BASE_URL}#{path}")
      uri.query = query if query && !query.empty?

      headers = HTTP::Headers{"Authorization" => "Bearer #{RightDesk::Auth.token!}"}
      headers["Content-Type"] = "application/json" if body

      response = HTTP::Client.exec(method, uri, headers: headers, body: body)
      Response.new(response.status_code, response.body)
    end
  end
end
