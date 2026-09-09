module RightDesk
  # Runtime config: API base URL resolution.
  #   --host override ▸ RIGHTDESK_URL env ▸ default
  # Override for self-hosted or local dev, e.g.
  #   rd whoami --host http://localhost:3000
  #   RIGHTDESK_URL=http://localhost:3000 rd whoami
  module Config
    DEFAULT_URL = "https://app.rightdesk.com"

    @@host_override : String? = nil

    def self.host_override=(value : String?)
      @@host_override = value
    end

    def self.base_url : String
      if (o = @@host_override) && !o.empty?
        return normalize(o)
      end
      if (env = ENV["RIGHTDESK_URL"]?) && !env.empty?
        return env
      end
      DEFAULT_URL
    end

    # Accept a full URL or a bare host; bare hosts default to https.
    private def self.normalize(host : String) : String
      return host if host.starts_with?("http://") || host.starts_with?("https://")
      "https://#{host}"
    end
  end
end
