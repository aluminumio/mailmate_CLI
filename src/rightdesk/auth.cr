require "uri"
require "./config"

module RightDesk
  # Static-token auth. RightDesk has no OAuth device flow (unlike the other org
  # CLIs), so a token is minted in the web UI (Organization Settings → API) and
  # pasted via `rd login`. It is persisted in ~/.netrc, keyed by the API
  # host, and sent as `Authorization: Bearer <token>` on every request.
  #
  # The token is org-scoped: to work in another organization, mint a token there
  # and `login` again (this overwrites the local entry). `logout` only clears the
  # local copy — the token stays valid server-side until revoked in the web UI.
  module Auth
    LOGIN = "api"

    @@token_override : String? = nil

    # Set by the `--token` global flag. Rarely used — prefer RIGHTDESK_TOKEN.
    def self.token_override=(value : String?)
      @@token_override = value
    end

    def self.host : String
      URI.parse(RightDesk::Config.base_url).host || "app.rightdesk.com"
    end

    def self.netrc_path : String
      home = ENV["HOME"]? || ENV["USERPROFILE"]?
      raise "Cannot locate home directory (HOME not set)" unless home
      File.join(home, ".netrc")
    end

    # Resolve the token: --token override ▸ RIGHTDESK_TOKEN env ▸ ~/.netrc.
    def self.token : String?
      if (o = @@token_override) && !o.empty?
        return o
      end
      if env = ENV["RIGHTDESK_TOKEN"]?
        return env unless env.empty?
      end
      parse[host]?.try(&.["password"]?)
    end

    def self.token! : String
      token || raise "Not authenticated. Run `rd login` first."
    end

    def self.store(token : String) : Nil
      entries = parse
      entries[host] = {"login" => LOGIN, "password" => token}
      write(entries)
    end

    def self.clear : Nil
      entries = parse
      entries.delete(host)
      write(entries)
    end

    # Tokenized netrc parse — handles both canonical (multi-line) and inline
    # entries. Returns machine => {field => value}. Comments and macdef bodies
    # are not preserved on rewrite (this tool manages netrc in canonical form).
    private def self.parse : Hash(String, Hash(String, String))
      result = Hash(String, Hash(String, String)).new
      return result unless File.exists?(netrc_path)

      tokens = File.read(netrc_path).split(/\s+/).reject(&.empty?)
      current : String? = nil
      i = 0
      while i < tokens.size
        case tokens[i]
        when "machine"
          i += 1
          name = tokens[i]?
          break unless name
          current = name
          result[current] = Hash(String, String).new
        when "default"
          current = "default"
          result[current] = Hash(String, String).new
        when "login", "password", "account"
          key = tokens[i]
          i += 1
          value = tokens[i]?
          if (c = current) && value
            result[c][key] = value
          end
        end
        i += 1
      end
      result
    end

    private def self.write(entries : Hash(String, Hash(String, String))) : Nil
      content = String.build do |s|
        entries.each do |machine, fields|
          s << (machine == "default" ? "default\n" : "machine #{machine}\n")
          fields.each { |k, v| s << "  #{k} #{v}\n" }
        end
      end
      File.write(netrc_path, content)
      File.chmod(netrc_path, 0o600)
    end
  end
end
