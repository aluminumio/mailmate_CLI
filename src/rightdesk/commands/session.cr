require "athena-console"
require "json"
require "../config"
require "../auth"
require "../client"

module RightDesk
  @[ACONA::AsCommand("skills", description: "Print the agent/LLM usage guide for this CLI")]
  class SkillsCommand < ACON::Command
    SKILL = {{ read_file "#{__DIR__}/../skill.md" }}

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      output.print SKILL
      ACON::Command::Status::SUCCESS
    end
  end

  @[ACONA::AsCommand("login", description: "Store an API token (minted in the web UI) for CLI use")]
  class LoginCommand < ACON::Command
    protected def configure : Nil
      self.argument("token", :optional, "API token (omit to be prompted)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      token = input.argument("token").to_s.presence
      unless token
        STDERR.print "Paste your RightDesk API token (Organization Settings → API): "
        token = read_secret
      end

      if token.nil? || token.empty?
        STDERR.puts "login failed: no token provided"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      RightDesk::Auth.store(token)

      resp = RightDesk::Client.get("/api/v1/me")
      unless resp.success?
        RightDesk.exit_code = RightDesk.status_for(resp.status)
        STDERR.puts "Stored token, but verification failed: HTTP #{resp.status}. Check the token and host (#{RightDesk::Config.base_url})."
        return ACON::Command::Status::FAILURE
      end

      me = JSON.parse(resp.body)
      email = me.dig?("user", "email").try(&.as_s?)
      org = me.dig?("organization", "name").try(&.as_s?)
      STDERR.puts "Logged in as #{email} · #{org} (#{RightDesk::Auth.host})"
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "login failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end

    private def read_secret : String?
      if STDIN.tty?
        value = STDIN.noecho { STDIN.gets }
        STDERR.print "\n"
        value.try(&.chomp)
      else
        STDIN.gets.try(&.chomp)
      end
    end
  end

  @[ACONA::AsCommand("logout", description: "Clear the locally stored API token")]
  class LogoutCommand < ACON::Command
    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      RightDesk::Auth.clear
      STDERR.puts "Logged out (local token cleared). The token remains valid until revoked in the web UI."
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "logout failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("whoami", description: "Show the authenticated user and organization")]
  class WhoamiCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      WhoamiCommand.add_json_option(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      resp = RightDesk::Client.get("/api/v1/me")
      return RightDesk.fail("whoami", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      me = JSON.parse(resp.body)
      email = me.dig?("user", "email").try(&.as_s?)
      org = me.dig?("organization", "name").try(&.as_s?)
      role = me.dig?("role").try(&.as_s?)
      output.puts "user:         #{email}"
      output.puts "organization: #{org}#{role ? " (#{role})" : ""}"
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "whoami failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end
end
