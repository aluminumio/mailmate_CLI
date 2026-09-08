require "athena-console"
require "json"
require "uri"
require "colorize"
require "./version"
require "./config"
require "./auth"
require "./client"

module RightDesk
  # Mixin for data-returning commands. Adds `--json/-j` and exposes `json?(input)`.
  module JSONOption
    macro included
      def self.add_json_option(cmd)
        cmd.option("json", "j", ACON::Input::Option::Value[:none], "Emit JSON instead of human-readable text")
      end
    end

    protected def json?(input : ACON::Input::Interface) : Bool
      input.option("json", Bool)
    end
  end

  # Uniform failure output. A 401 means the token is missing/invalid/revoked —
  # nudge the user to re-login rather than dumping the raw body.
  def self.fail(output : ACON::Output::Interface, label : String, resp : Client::Response) : ACON::Command::Status
    if resp.status == 401
      output.puts "#{label} failed: not authenticated (HTTP 401). Run `rightdesk login`."
    else
      output.puts "#{label} failed: HTTP #{resp.status} — #{resp.body}"
    end
    ACON::Command::Status::FAILURE
  end

  module CLI
    def self.run(argv : Array(String)) : Nil
      app = ACON::Application.new("rightdesk", CLI_VERSION)
      app.add LoginCommand.new
      app.add LogoutCommand.new
      app.add WhoamiCommand.new
      app.add SkillsCommand.new
      app.add DealsCommand.new
      app.add DealsShowCommand.new
      app.add ContactsCommand.new
      app.add ContactsSearchCommand.new
      app.add ContactsShowCommand.new
      app.add PipelinesCommand.new
      app.add PipelinesShowCommand.new
      app.run(ACON::Input::ARGV.new(argv))
    end
  end

  @[ACONA::AsCommand("skills", description: "Print the agent/LLM usage guide for this CLI")]
  class SkillsCommand < ACON::Command
    SKILL = {{ read_file "#{__DIR__}/skill.md" }}

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
        output.print "Paste your RightDesk API token (Organization Settings → API): "
        token = read_secret
      end

      if token.nil? || token.empty?
        output.puts "login failed: no token provided"
        return ACON::Command::Status::FAILURE
      end

      RightDesk::Auth.store(token)

      resp = RightDesk::Client.get("/api/v1/me")
      unless resp.success?
        output.puts "Stored token, but verification failed: HTTP #{resp.status}. Check the token and RIGHTDESK_URL (#{RightDesk::BASE_URL})."
        return ACON::Command::Status::FAILURE
      end

      me = JSON.parse(resp.body)
      email = me.dig?("user", "email").try(&.as_s?)
      org = me.dig?("organization", "name").try(&.as_s?)
      output.puts "Logged in as #{email} · #{org} (#{RightDesk::Auth.host})"
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "login failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end

    private def read_secret : String?
      if STDIN.tty?
        value = STDIN.noecho { STDIN.gets }
        print "\n"
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
      output.puts "Logged out (local token cleared). The token remains valid until revoked in the web UI."
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "logout failed: #{ex.message}"
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
      return RightDesk.fail(output, "whoami", resp) unless resp.success?

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
      output.puts "whoami failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("deals:list|deals", description: "List deals (newest first)")]
  class DealsCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      DealsCommand.add_json_option(self)
      self
        .option("status", nil, ACON::Input::Option::Value[:required], "Filter by status: open, won, lost")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if s = input.option("status").to_s.presence
          form.add("status", s)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
      end

      resp = RightDesk::Client.get("/api/v1/deals", params)
      return RightDesk.fail(output, "deals", resp) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      deals = parsed["deals"]?.try(&.as_a?) || [] of JSON::Any

      output.puts ""
      output.puts String.build { |s|
        s << "  "
        s << "ID".ljust(8).colorize(:white).mode(:bold)
        s << "Title".ljust(32).colorize(:white).mode(:bold)
        s << "Value".ljust(16).colorize(:white).mode(:bold)
        s << "Status".ljust(8).colorize(:white).mode(:bold)
        s << "Stage".colorize(:white).mode(:bold)
      }
      output.puts "  #{"─" * 78}"

      deals.each do |d|
        id = d["id"]?.try(&.to_s) || "?"
        title = d["title"]?.try(&.as_s?) || "—"
        value = d["value"]?.try(&.to_s) || "0"
        currency = d["currency"]?.try(&.as_s?) || ""
        status = d["status"]?.try(&.as_s?) || ""
        stage = d["stage_name"]?.try(&.as_s?) || ""

        output.puts String.build { |s|
          s << "  "
          s << id.ljust(8)
          s << (title.size > 30 ? "#{title[0..29]}…" : title).ljust(32)
          s << "#{value} #{currency}".ljust(16)
          s << status.ljust(8).colorize(status == "won" ? :green : status == "lost" ? :red : :yellow)
          s << stage
        }
      end

      if meta = parsed["meta"]?
        output.puts ""
        output.puts "  #{meta["total_count"]?} deals — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      output.puts ""
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "deals failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("deals:show", description: "Show a single deal by ID")]
  class DealsShowCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      DealsShowCommand.add_json_option(self)
      self.argument("id", :required, "deal ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/deals/#{URI.encode_path(id)}")
      return RightDesk.fail(output, "deals:show", resp) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      d = JSON.parse(resp.body)["deal"]?
      unless d
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", d["id"]?)
      show.call("title", d["title"]?)
      show.call("value", d["value"]?)
      show.call("currency", d["currency"]?)
      show.call("status", d["status"]?)
      show.call("probability", d["probability"]?)
      show.call("stage", d["stage_name"]?)
      show.call("pipeline", d["pipeline_name"]?)
      show.call("owner", d["owner_name"]?)
      show.call("contact", d["contact_name"]?)
      show.call("contact_email", d["contact_email"]?)
      show.call("company", d["company_name"]?)
      show.call("expected_close_date", d["expected_close_date"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "deals:show failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:list|contacts", description: "List contacts (newest first)")]
  class ContactsCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsCommand.add_json_option(self)
      self.option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
      end
      resp = RightDesk::Client.get("/api/v1/contacts", params)
      return RightDesk.fail(output, "contacts", resp) unless resp.success?
      RightDesk.print_contacts(input, output, resp, "contacts")
    rescue ex
      output.puts "contacts failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:search", description: "Search contacts by name, email, or phone")]
  class ContactsSearchCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsSearchCommand.add_json_option(self)
      self
        .argument("query", :required, "search term (matched against email, first/last name)")
        .option("company", nil, ACON::Input::Option::Value[:required], "filter by company ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      query = input.argument("query").to_s
      # The API searches per-field; fan the single query term across name+email.
      params = URI::Params.build do |form|
        form.add("first_name", query)
        form.add("last_name", query)
        form.add("email", query)
        if c = input.option("company").to_s.presence
          form.add("company_id", c)
        end
      end
      resp = RightDesk::Client.get("/api/v1/contacts/search", params)
      return RightDesk.fail(output, "contacts:search", resp) unless resp.success?
      RightDesk.print_contacts(input, output, resp, "contacts:search")
    rescue ex
      output.puts "contacts:search failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:show", description: "Show a single contact by ID")]
  class ContactsShowCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsShowCommand.add_json_option(self)
      self.argument("id", :required, "contact ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/contacts/#{URI.encode_path(id)}")
      return RightDesk.fail(output, "contacts:show", resp) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      c = JSON.parse(resp.body)["contact"]?
      unless c
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      name = "#{c["first_name"]?.try(&.as_s?)} #{c["last_name"]?.try(&.as_s?)}".strip
      output.puts "name: #{name}" unless name.empty?
      show.call("id", c["id"]?)
      show.call("email", c["email"]?)
      show.call("phone", c["phone"]?)
      show.call("company", c["company_name"]?)
      show.call("linkedin", c["linkedin_profile"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "contacts:show failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  # Shared contact-list renderer for `contacts` and `contacts:search`.
  def self.print_contacts(input : ACON::Input::Interface, output : ACON::Output::Interface,
                          resp : Client::Response, label : String) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
      return ACON::Command::Status::SUCCESS
    end

    parsed = JSON.parse(resp.body)
    contacts = parsed["contacts"]?.try(&.as_a?) || [] of JSON::Any

    contacts.each do |c|
      id = c["id"]?.try(&.to_s) || "?"
      name = "#{c["first_name"]?.try(&.as_s?)} #{c["last_name"]?.try(&.as_s?)}".strip
      email = c["email"]?.try(&.as_s?) || ""
      company = c["company_name"]?.try(&.as_s?)
      line = "#{id}\t#{name.empty? ? email : name}\t#{email}"
      line += "\t#{company}" if company && !company.empty?
      output.puts line
    end

    if meta = parsed["meta"]?
      output.puts ""
      output.puts "#{meta["total_count"]?} contacts — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("pipelines:list|pipelines", description: "List sales pipelines")]
  class PipelinesCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesCommand.add_json_option(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      resp = RightDesk::Client.get("/api/v1/pipelines")
      return RightDesk.fail(output, "pipelines", resp) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      (JSON.parse(resp.body)["pipelines"]?.try(&.as_a?) || [] of JSON::Any).each do |p|
        output.puts "#{p["id"]?}\t#{p["name"]?.try(&.as_s?)}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "pipelines failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("pipelines:show", description: "Show a pipeline and its stages")]
  class PipelinesShowCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesShowCommand.add_json_option(self)
      self.argument("id", :required, "pipeline ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/pipelines/#{URI.encode_path(id)}")
      return RightDesk.fail(output, "pipelines:show", resp) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      p = JSON.parse(resp.body)["pipeline"]?
      unless p
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      output.puts "#{p["id"]?}\t#{p["name"]?.try(&.as_s?)}"
      output.puts ""
      output.puts "Stages:"
      (p["stages"]?.try(&.as_a?) || [] of JSON::Any).each do |st|
        output.puts "  #{st["position"]?}. #{st["name"]?.try(&.as_s?)} (#{st["stage_type"]?.try(&.as_s?)}, #{st["probability"]?}%)"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      output.puts "pipelines:show failed: #{ex.message}"
      ACON::Command::Status::FAILURE
    end
  end
end
