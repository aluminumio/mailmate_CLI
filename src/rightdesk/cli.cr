require "athena-console"
require "json"
require "uri"
require "colorize"
require "./version"
require "./config"
require "./auth"
require "./client"

module RightDesk
  # Process exit code, set by command failures and read by `CLI.run`.
  # 0 ok · 1 general · 2 usage · 3 auth(401) · 4 not-found(404) · 5 insufficient-scope(403).
  @@exit_code : Int32? = nil

  def self.exit_code=(code : Int32)
    @@exit_code = code
  end

  def self.exit_code? : Int32?
    @@exit_code
  end

  def self.status_for(http : Int32) : Int32
    case http
    when 401 then 3
    when 403 then 5
    when 404 then 4
    else          1
    end
  end

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

  # Uniform failure output → STDERR (diagnostics never touch stdout). Records the
  # mapped exit code. Under --json, emits a structured `{error,code,hint?}` object.
  def self.fail(label : String, resp : Client::Response, json : Bool = false) : ACON::Command::Status
    RightDesk.exit_code = status_for(resp.status)
    if json
      obj = Hash(String, String).new
      obj["error"] = error_message(resp)
      obj["code"] = error_code(resp)
      obj["hint"] = "Run `rd login`." if resp.status == 401
      STDERR.puts obj.to_json
    elsif resp.status == 401
      STDERR.puts "#{label} failed: not authenticated (HTTP 401). Run `rd login`."
    else
      STDERR.puts "#{label} failed: HTTP #{resp.status} — #{resp.body}"
    end
    ACON::Command::Status::FAILURE
  end

  def self.error_code(resp : Client::Response) : String
    if (parsed = JSON.parse(resp.body) rescue nil) && (c = parsed["code"]?.try(&.as_s?))
      return c
    end
    case resp.status
    when 401 then "unauthorized"
    when 403 then "forbidden"
    when 404 then "not_found"
    when 422 then "validation_error"
    else          "error"
    end
  end

  def self.error_message(resp : Client::Response) : String
    if (parsed = JSON.parse(resp.body) rescue nil) && (m = parsed["error"]?.try(&.as_s?))
      return m
    end
    "HTTP #{resp.status}"
  end

  module CLI
    # Registered command names, used by the ARGV rewriter to validate joins.
    COMMAND_NAMES = %w[
      login logout whoami skills
      deals:list deals:get
      contacts:list contacts:get contacts:search contacts:create contacts:update contacts:merge
      companies:list companies:get companies:create companies:update
      customers:list customers:get customers:create customers:update customers:timeline
      partners:list partners:get partners:create partners:update partners:timeline
      pipelines:list pipelines:get pipelines:create pipelines:update pipelines:delete
      stages:list stages:create stages:update stages:reorder stages:delete
      products:list products:get products:create products:update products:activate products:deactivate products:delete
    ]

    def self.run(argv : Array(String)) : Nil
      app = ACON::Application.new("rd", CLI_VERSION)
      app.auto_exit = false
      app.add LoginCommand.new
      app.add LogoutCommand.new
      app.add WhoamiCommand.new
      app.add SkillsCommand.new
      app.add DealsListCommand.new
      app.add DealsGetCommand.new
      app.add ContactsListCommand.new
      app.add ContactsSearchCommand.new
      app.add ContactsGetCommand.new
      app.add ContactsCreateCommand.new
      app.add ContactsUpdateCommand.new
      app.add ContactsMergeCommand.new
      app.add CustomersListCommand.new
      app.add CustomersGetCommand.new
      app.add CustomersCreateCommand.new
      app.add CustomersUpdateCommand.new
      app.add CustomersTimelineCommand.new
      app.add PartnersListCommand.new
      app.add PartnersGetCommand.new
      app.add PartnersCreateCommand.new
      app.add PartnersUpdateCommand.new
      app.add PartnersTimelineCommand.new
      app.add CompaniesListCommand.new
      app.add CompaniesGetCommand.new
      app.add CompaniesCreateCommand.new
      app.add CompaniesUpdateCommand.new
      app.add PipelinesListCommand.new
      app.add PipelinesGetCommand.new
      app.add PipelinesCreateCommand.new
      app.add PipelinesUpdateCommand.new
      app.add PipelinesDeleteCommand.new
      app.add StagesListCommand.new
      app.add StagesCreateCommand.new
      app.add StagesUpdateCommand.new
      app.add StagesReorderCommand.new
      app.add StagesDeleteCommand.new
      app.add ProductsListCommand.new
      app.add ProductsGetCommand.new
      app.add ProductsCreateCommand.new
      app.add ProductsUpdateCommand.new
      app.add ProductsActivateCommand.new
      app.add ProductsDeactivateCommand.new
      app.add ProductsDeleteCommand.new

      status = app.run(ACON::Input::ARGV.new(preprocess(argv)))
      exit(RightDesk.exit_code? || status.value)
    end

    # Pull out global flags (`--host`, `--token`), then rewrite `<noun> <verb>` to
    # the colon form athena understands.
    def self.preprocess(argv : Array(String)) : Array(String)
      join_noun_verb(extract_global_flags(argv))
    end

    # Extract and apply `--host`/`--token` (either `--flag value` or `--flag=value`),
    # returning the remaining tokens. These are framework-global, so we handle them
    # here rather than declaring them on every command.
    def self.extract_global_flags(argv : Array(String)) : Array(String)
      result = [] of String
      i = 0
      while i < argv.size
        arg = argv[i]
        if arg == "--host" || arg == "--token"
          i += 1
          apply_global(arg, argv[i]?)
        elsif arg.starts_with?("--host=")
          apply_global("--host", arg.split("=", 2)[1])
        elsif arg.starts_with?("--token=")
          apply_global("--token", arg.split("=", 2)[1])
        else
          result << arg
        end
        i += 1
      end
      result
    end

    private def self.apply_global(key : String, value : String?)
      return unless value
      case key
      when "--host"  then RightDesk::Config.host_override = value
      when "--token" then RightDesk::Auth.token_override = value
      end
    end

    # Join the leading non-flag tokens with `:` when they form a registered command.
    # `deals get 5` → `deals:get 5`; bare/unknown/colon forms pass through unchanged.
    def self.join_noun_verb(argv : Array(String)) : Array(String)
      lead = [] of String
      argv.each do |t|
        break if t.starts_with?("-")
        lead << t
      end
      return argv if lead.size < 2

      max = Math.min(3, lead.size)
      max.downto(2) do |k|
        candidate = lead[0, k].join(":")
        return [candidate] + argv[k..] if COMMAND_NAMES.includes?(candidate)
      end
      argv
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

  @[ACONA::AsCommand("deals:list", description: "List deals (newest first)")]
  class DealsListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      DealsListCommand.add_json_option(self)
      self
        .option("status", nil, ACON::Input::Option::Value[:required], "Filter by status: open, won, lost")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if s = input.option("status").to_s.presence
          form.add("status", s)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/deals", params)
      return RightDesk.fail("deals:list", resp, json?(input)) unless resp.success?

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
      STDERR.puts "deals:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("deals:get", description: "Show a single deal by ID")]
  class DealsGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      DealsGetCommand.add_json_option(self)
      self.argument("id", :required, "deal ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/deals/#{URI.encode_path(id)}")
      return RightDesk.fail("deals:get", resp, json?(input)) unless resp.success?

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
      STDERR.puts "deals:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:list", description: "List contacts (newest first)")]
  class ContactsListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsListCommand.add_json_option(self)
      self
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end
      resp = RightDesk::Client.get("/api/v1/contacts", params)
      return RightDesk.fail("contacts:list", resp, json?(input)) unless resp.success?
      RightDesk.print_contacts(input, output, resp)
    rescue ex
      STDERR.puts "contacts:list failed: #{ex.message}"
      RightDesk.exit_code = 1
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
      return RightDesk.fail("contacts:search", resp, json?(input)) unless resp.success?
      RightDesk.print_contacts(input, output, resp)
    rescue ex
      STDERR.puts "contacts:search failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:get", description: "Show a single contact by ID")]
  class ContactsGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsGetCommand.add_json_option(self)
      self.argument("id", :required, "contact ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/contacts/#{URI.encode_path(id)}")
      return RightDesk.fail("contacts:get", resp, json?(input)) unless resp.success?

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
      STDERR.puts "contacts:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # Shared contact-list renderer for `contacts:list` and `contacts:search`.
  def self.print_contacts(input : ACON::Input::Interface, output : ACON::Output::Interface,
                          resp : Client::Response) : ACON::Command::Status
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

  @[ACONA::AsCommand("pipelines:list", description: "List sales pipelines")]
  class PipelinesListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesListCommand.add_json_option(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      resp = RightDesk::Client.get("/api/v1/pipelines")
      return RightDesk.fail("pipelines:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      (JSON.parse(resp.body)["pipelines"]?.try(&.as_a?) || [] of JSON::Any).each do |p|
        output.puts "#{p["id"]?}\t#{p["name"]?.try(&.as_s?)}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "pipelines:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("pipelines:get", description: "Show a pipeline and its stages")]
  class PipelinesGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesGetCommand.add_json_option(self)
      self.argument("id", :required, "pipeline ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/pipelines/#{URI.encode_path(id)}")
      return RightDesk.fail("pipelines:get", resp, json?(input)) unless resp.success?

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
      STDERR.puts "pipelines:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # Build a company attribute hash from the set --flags (only provided fields).
  # Shared by companies:create and companies:update.
  def self.company_body(input : ACON::Input::Interface) : Hash(String, String)
    mapping = {
      "name"        => "name",
      "domain"      => "company_domain_name",
      "url"         => "company_url",
      "type"        => "company_type",
      "industry"    => "industry",
      "phone"       => "phone",
      "city"        => "city",
      "country"     => "country",
      "postal-code" => "postal_code",
      "employees"   => "total_employee",
      "description" => "description",
      "owner"       => "owner",
      "external-id" => "external_record_id",
    }
    company = Hash(String, String).new
    mapping.each do |opt, field|
      if value = input.option(opt).to_s.presence
        company[field] = value
      end
    end
    company
  end

  # Shared option set for companies:create / companies:update.
  def self.configure_company_options(cmd : ACON::Command) : Nil
    cmd.option("name", nil, ACON::Input::Option::Value[:required], "Company name")
    cmd.option("domain", nil, ACON::Input::Option::Value[:required], "Company domain")
    cmd.option("url", nil, ACON::Input::Option::Value[:required], "Website URL")
    cmd.option("industry", nil, ACON::Input::Option::Value[:required], "Industry")
    cmd.option("phone", nil, ACON::Input::Option::Value[:required], "Phone")
    cmd.option("city", nil, ACON::Input::Option::Value[:required], "City")
    cmd.option("country", nil, ACON::Input::Option::Value[:required], "Country")
    cmd.option("postal-code", nil, ACON::Input::Option::Value[:required], "Postal code")
    cmd.option("employees", nil, ACON::Input::Option::Value[:required], "Total employees")
    cmd.option("type", nil, ACON::Input::Option::Value[:required], "Company type")
    cmd.option("description", nil, ACON::Input::Option::Value[:required], "Description")
    cmd.option("owner", nil, ACON::Input::Option::Value[:required], "Owner")
    cmd.option("external-id", nil, ACON::Input::Option::Value[:required], "Idempotency key (external_record_id)")
  end

  # Print a created/updated company (tab id\tname) or raw JSON under --json.
  def self.print_company_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      c = JSON.parse(resp.body)["company"]?
      if c
        output.puts "#{c["id"]?}\t#{c["name"]?.try(&.as_s?)}"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("companies:list", description: "List companies (newest first)")]
  class CompaniesListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CompaniesListCommand.add_json_option(self)
      self
        .option("search", nil, ACON::Input::Option::Value[:required], "Filter by name or domain")
        .option("industry", nil, ACON::Input::Option::Value[:required], "Filter by industry")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if s = input.option("search").to_s.presence
          form.add("search", s)
        end
        if i = input.option("industry").to_s.presence
          form.add("industry", i)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/companies", params)
      return RightDesk.fail("companies:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      companies = parsed["companies"]?.try(&.as_a?) || [] of JSON::Any
      companies.each do |c|
        id = c["id"]?.try(&.to_s) || "?"
        name = c["name"]?.try(&.as_s?) || "—"
        industry = c["industry"]?.try(&.as_s?) || ""
        domain = c["company_domain_name"]?.try(&.as_s?) || ""
        line = "#{id}\t#{name}"
        line += "\t#{industry}" unless industry.empty?
        line += "\t#{domain}" unless domain.empty?
        output.puts line
      end

      if meta = parsed["meta"]?
        output.puts ""
        output.puts "#{meta["total_count"]?} companies — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "companies:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("companies:get", description: "Show a single company by ID")]
  class CompaniesGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CompaniesGetCommand.add_json_option(self)
      self.argument("id", :required, "company ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/companies/#{URI.encode_path(id)}")
      return RightDesk.fail("companies:get", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      c = JSON.parse(resp.body)["company"]?
      unless c
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", c["id"]?)
      show.call("name", c["name"]?)
      show.call("industry", c["industry"]?)
      show.call("domain", c["company_domain_name"]?)
      show.call("url", c["company_url"]?)
      show.call("type", c["company_type"]?)
      show.call("phone", c["phone"]?)
      show.call("city", c["city"]?)
      show.call("country", c["country"]?)
      show.call("owner", c["owner"]?)
      show.call("external_id", c["external_record_id"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "companies:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("companies:create", description: "Create a company")]
  class CompaniesCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CompaniesCreateCommand.add_json_option(self)
      RightDesk.configure_company_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      company = RightDesk.company_body(input)
      unless company.has_key?("name")
        STDERR.puts "companies:create failed: --name is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/companies", {"company" => company}.to_json)
      return RightDesk.fail("companies:create", resp, json?(input)) unless resp.success?
      RightDesk.print_company_result(input, output, resp)
    rescue ex
      STDERR.puts "companies:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("companies:update", description: "Update a company by ID")]
  class CompaniesUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CompaniesUpdateCommand.add_json_option(self)
      self.argument("id", :required, "company ID")
      RightDesk.configure_company_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      company = RightDesk.company_body(input)
      if company.empty?
        STDERR.puts "companies:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/companies/#{URI.encode_path(id)}", {"company" => company}.to_json)
      return RightDesk.fail("companies:update", resp, json?(input)) unless resp.success?
      RightDesk.print_company_result(input, output, resp)
    rescue ex
      STDERR.puts "companies:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # Build a pipeline attribute hash from the set --flags (only provided fields).
  # Shared by pipelines:create and pipelines:update.
  def self.pipeline_body(input : ACON::Input::Interface) : Hash(String, String | Bool | Int32)
    pipeline = Hash(String, String | Bool | Int32).new
    if value = input.option("name").to_s.presence
      pipeline["name"] = value
    end
    if value = input.option("entity").to_s.presence
      pipeline["entity_type"] = value
    end
    if value = input.option("description").to_s.presence
      pipeline["description"] = value
    end
    pipeline["is_default"] = true if input.option("default", Bool)
    if input.option("inactive", Bool)
      pipeline["active"] = false
    elsif input.option("active", Bool)
      pipeline["active"] = true
    end
    if (value = input.option("position").to_s.presence) && (n = value.to_i?)
      pipeline["position"] = n
    end
    pipeline
  end

  # Shared option set for pipelines:create / pipelines:update.
  def self.configure_pipeline_options(cmd : ACON::Command) : Nil
    cmd.option("name", nil, ACON::Input::Option::Value[:required], "Pipeline name")
    cmd.option("entity", nil, ACON::Input::Option::Value[:required], "Entity type: deal or lead (create)")
    cmd.option("description", nil, ACON::Input::Option::Value[:required], "Description")
    cmd.option("default", nil, ACON::Input::Option::Value[:none], "Make this the default pipeline for its entity type")
    cmd.option("active", nil, ACON::Input::Option::Value[:none], "Mark active")
    cmd.option("inactive", nil, ACON::Input::Option::Value[:none], "Mark inactive")
    cmd.option("position", nil, ACON::Input::Option::Value[:required], "Sort position")
  end

  # Print a created/updated pipeline (tab id\tname (entity)) or raw JSON under --json.
  def self.print_pipeline_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      p = JSON.parse(resp.body)["pipeline"]?
      if p
        output.puts "#{p["id"]?}\t#{p["name"]?.try(&.as_s?)} (#{p["entity_type"]?.try(&.as_s?)})"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("pipelines:create", description: "Create a pipeline")]
  class PipelinesCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesCreateCommand.add_json_option(self)
      RightDesk.configure_pipeline_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      pipeline = RightDesk.pipeline_body(input)
      unless pipeline.has_key?("name")
        STDERR.puts "pipelines:create failed: --name is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/pipelines", {"pipeline" => pipeline}.to_json)
      return RightDesk.fail("pipelines:create", resp, json?(input)) unless resp.success?
      RightDesk.print_pipeline_result(input, output, resp)
    rescue ex
      STDERR.puts "pipelines:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("pipelines:update", description: "Update a pipeline by ID")]
  class PipelinesUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesUpdateCommand.add_json_option(self)
      self.argument("id", :required, "pipeline ID")
      RightDesk.configure_pipeline_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      pipeline = RightDesk.pipeline_body(input)
      if pipeline.empty?
        STDERR.puts "pipelines:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/pipelines/#{URI.encode_path(id)}", {"pipeline" => pipeline}.to_json)
      return RightDesk.fail("pipelines:update", resp, json?(input)) unless resp.success?
      RightDesk.print_pipeline_result(input, output, resp)
    rescue ex
      STDERR.puts "pipelines:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("pipelines:delete", description: "Delete a pipeline by ID (requires --yes)")]
  class PipelinesDeleteCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PipelinesDeleteCommand.add_json_option(self)
      self.argument("id", :required, "pipeline ID")
      self.option("yes", "y", ACON::Input::Option::Value[:none], "Confirm deletion (required)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      unless input.option("yes", Bool)
        STDERR.puts "pipelines:delete failed: refusing to delete without --yes"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.delete("/api/v1/pipelines/#{URI.encode_path(id)}")
      return RightDesk.fail("pipelines:delete", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts({"id" => id, "deleted" => true}.to_json)
      else
        output.puts "deleted #{id}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "pipelines:delete failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # ----- stages (nested under a pipeline; every command needs --pipeline) -----

  # Build a stage attribute hash from the set --flags (only provided fields).
  # Shared by stages:create and stages:update.
  def self.stage_body(input : ACON::Input::Interface) : Hash(String, String | Int32)
    stage = Hash(String, String | Int32).new
    if v = input.option("name").to_s.presence
      stage["name"] = v
    end
    if v = input.option("stage-type").to_s.presence
      stage["stage_type"] = v
    end
    if v = input.option("color").to_s.presence
      stage["color"] = v
    end
    if (v = input.option("probability").to_s.presence) && (n = v.to_i?)
      stage["probability"] = n
    end
    if (v = input.option("rotting-days").to_s.presence) && (n = v.to_i?)
      stage["rotting_days"] = n
    end
    if (v = input.option("position").to_s.presence) && (n = v.to_i?)
      stage["position"] = n
    end
    stage
  end

  # Body option set for stages:create / stages:update (excludes --pipeline).
  def self.configure_stage_options(cmd : ACON::Command) : Nil
    cmd.option("name", nil, ACON::Input::Option::Value[:required], "Stage name")
    cmd.option("stage-type", nil, ACON::Input::Option::Value[:required], "Stage type: open, won, or lost")
    cmd.option("color", nil, ACON::Input::Option::Value[:required], "Color (hex)")
    cmd.option("probability", nil, ACON::Input::Option::Value[:required], "Win probability 0-100")
    cmd.option("rotting-days", nil, ACON::Input::Option::Value[:required], "Rotting days")
    cmd.option("position", nil, ACON::Input::Option::Value[:required], "Sort position")
  end

  # The required --pipeline reference every stage command shares.
  def self.configure_pipeline_ref(cmd : ACON::Command) : Nil
    cmd.option("pipeline", nil, ACON::Input::Option::Value[:required], "Pipeline ID (required)")
  end

  # Print a created/updated stage (tab id\tname) or raw JSON under --json.
  def self.print_stage_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      s = JSON.parse(resp.body)["stage"]?
      if s
        output.puts "#{s["id"]?}\t#{s["name"]?.try(&.as_s?)}"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("stages:list", description: "List a pipeline's stages (by position)")]
  class StagesListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      StagesListCommand.add_json_option(self)
      RightDesk.configure_pipeline_ref(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      pid = input.option("pipeline").to_s.presence
      unless pid
        STDERR.puts "stages:list failed: --pipeline is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.get("/api/v1/pipelines/#{URI.encode_path(pid)}/stages")
      return RightDesk.fail("stages:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      (JSON.parse(resp.body)["stages"]?.try(&.as_a?) || [] of JSON::Any).each do |s|
        output.puts "#{s["id"]?}\t#{s["name"]?.try(&.as_s?)} (#{s["stage_type"]?.try(&.as_s?)}, #{s["probability"]?}%)"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "stages:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("stages:create", description: "Create a stage in a pipeline")]
  class StagesCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      StagesCreateCommand.add_json_option(self)
      RightDesk.configure_pipeline_ref(self)
      RightDesk.configure_stage_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      pid = input.option("pipeline").to_s.presence
      unless pid
        STDERR.puts "stages:create failed: --pipeline is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      stage = RightDesk.stage_body(input)
      unless stage.has_key?("name")
        STDERR.puts "stages:create failed: --name is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/pipelines/#{URI.encode_path(pid)}/stages", {"stage" => stage}.to_json)
      return RightDesk.fail("stages:create", resp, json?(input)) unless resp.success?
      RightDesk.print_stage_result(input, output, resp)
    rescue ex
      STDERR.puts "stages:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("stages:update", description: "Update a stage by ID")]
  class StagesUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      StagesUpdateCommand.add_json_option(self)
      self.argument("id", :required, "stage ID")
      RightDesk.configure_pipeline_ref(self)
      RightDesk.configure_stage_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      pid = input.option("pipeline").to_s.presence
      unless pid
        STDERR.puts "stages:update failed: --pipeline is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      id = input.argument("id").to_s
      stage = RightDesk.stage_body(input)
      if stage.empty?
        STDERR.puts "stages:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/pipelines/#{URI.encode_path(pid)}/stages/#{URI.encode_path(id)}", {"stage" => stage}.to_json)
      return RightDesk.fail("stages:update", resp, json?(input)) unless resp.success?
      RightDesk.print_stage_result(input, output, resp)
    rescue ex
      STDERR.puts "stages:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("stages:reorder", description: "Reorder a pipeline's stages")]
  class StagesReorderCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      StagesReorderCommand.add_json_option(self)
      RightDesk.configure_pipeline_ref(self)
      self.option("order", nil, ACON::Input::Option::Value[:required], "Comma-separated stage IDs in the new order")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      pid = input.option("pipeline").to_s.presence
      unless pid
        STDERR.puts "stages:reorder failed: --pipeline is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      order = input.option("order").to_s.presence
      unless order
        STDERR.puts "stages:reorder failed: --order is required (comma-separated stage IDs)"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      nums = order.split(",").map(&.strip).reject(&.empty?).map(&.to_i?)
      if nums.empty? || nums.any?(&.nil?)
        STDERR.puts "stages:reorder failed: --order must be comma-separated integers"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      body = {"stages" => nums.map(&.not_nil!)}
      resp = RightDesk::Client.post("/api/v1/pipelines/#{URI.encode_path(pid)}/stages/reorder", body.to_json)
      return RightDesk.fail("stages:reorder", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      (JSON.parse(resp.body)["stages"]?.try(&.as_a?) || [] of JSON::Any).each do |s|
        output.puts "#{s["position"]?}\t#{s["name"]?.try(&.as_s?)}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "stages:reorder failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("stages:delete", description: "Delete a stage by ID (requires --yes)")]
  class StagesDeleteCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      StagesDeleteCommand.add_json_option(self)
      self.argument("id", :required, "stage ID")
      RightDesk.configure_pipeline_ref(self)
      self.option("yes", "y", ACON::Input::Option::Value[:none], "Confirm deletion (required)")
      self.option("transfer-to", nil, ACON::Input::Option::Value[:required], "Move active deals/leads to this stage ID first")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      pid = input.option("pipeline").to_s.presence
      unless pid
        STDERR.puts "stages:delete failed: --pipeline is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      id = input.argument("id").to_s
      unless input.option("yes", Bool)
        STDERR.puts "stages:delete failed: refusing to delete without --yes"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      path = "/api/v1/pipelines/#{URI.encode_path(pid)}/stages/#{URI.encode_path(id)}"
      if transfer = input.option("transfer-to").to_s.presence
        path += "?transfer_to=#{URI.encode_www_form(transfer)}"
      end

      resp = RightDesk::Client.delete(path)
      return RightDesk.fail("stages:delete", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts({"id" => id, "deleted" => true}.to_json)
      else
        output.puts "deleted #{id}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "stages:delete failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # ----- products -----

  # Build a product attribute hash from the set --flags (only provided fields).
  # Shared by products:create and products:update.
  def self.product_body(input : ACON::Input::Interface) : Hash(String, String | Bool | Int32)
    product = Hash(String, String | Bool | Int32).new
    {
      "name"              => "name",
      "code"              => "code",
      "category"          => "category",
      "description"       => "description",
      "price"             => "price",
      "currency"          => "currency",
      "tax"               => "tax",
      "unit"              => "unit",
      "billing-frequency" => "billing_frequency",
      "visible-to"        => "visible_to",
      "external-id"       => "external_record_id",
    }.each do |opt, field|
      if v = input.option(opt).to_s.presence
        product[field] = v
      end
    end
    if (v = input.option("billing-cycles").to_s.presence) && (n = v.to_i?)
      product["billing_cycles"] = n
    end
    if (v = input.option("owner-id").to_s.presence) && (n = v.to_i?)
      product["owner_id"] = n
    end
    if input.option("inactive", Bool)
      product["active"] = false
    elsif input.option("active", Bool)
      product["active"] = true
    end
    product
  end

  # Shared option set for products:create / products:update.
  def self.configure_product_options(cmd : ACON::Command) : Nil
    cmd.option("name", nil, ACON::Input::Option::Value[:required], "Product name")
    cmd.option("code", nil, ACON::Input::Option::Value[:required], "Product code/SKU")
    cmd.option("category", nil, ACON::Input::Option::Value[:required], "Category")
    cmd.option("description", nil, ACON::Input::Option::Value[:required], "Description")
    cmd.option("price", nil, ACON::Input::Option::Value[:required], "Price")
    cmd.option("currency", nil, ACON::Input::Option::Value[:required], "Currency (3-letter)")
    cmd.option("tax", nil, ACON::Input::Option::Value[:required], "Tax percentage 0-100")
    cmd.option("unit", nil, ACON::Input::Option::Value[:required], "Unit")
    cmd.option("billing-frequency", nil, ACON::Input::Option::Value[:required], "one_time, monthly, quarterly, or annually")
    cmd.option("billing-cycles", nil, ACON::Input::Option::Value[:required], "Number of billing cycles")
    cmd.option("visible-to", nil, ACON::Input::Option::Value[:required], "owner, team, or everyone")
    cmd.option("owner-id", nil, ACON::Input::Option::Value[:required], "Owner user ID")
    cmd.option("external-id", nil, ACON::Input::Option::Value[:required], "Idempotency key (external_record_id)")
    cmd.option("active", nil, ACON::Input::Option::Value[:none], "Mark active")
    cmd.option("inactive", nil, ACON::Input::Option::Value[:none], "Mark inactive")
  end

  # Print a created/updated/activated product (tab id\tname) or raw JSON under --json.
  def self.print_product_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      p = JSON.parse(resp.body)["product"]?
      if p
        output.puts "#{p["id"]?}\t#{p["name"]?.try(&.as_s?)}"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("products:list", description: "List products (newest first)")]
  class ProductsListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsListCommand.add_json_option(self)
      self
        .option("active", nil, ACON::Input::Option::Value[:none], "Only active products")
        .option("inactive", nil, ACON::Input::Option::Value[:none], "Only inactive products")
        .option("category", nil, ACON::Input::Option::Value[:required], "Filter by category")
        .option("search", nil, ACON::Input::Option::Value[:required], "Filter by name, code, or category")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if input.option("inactive", Bool)
          form.add("active", "false")
        elsif input.option("active", Bool)
          form.add("active", "true")
        end
        if c = input.option("category").to_s.presence
          form.add("category", c)
        end
        if s = input.option("search").to_s.presence
          form.add("search", s)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/products", params)
      return RightDesk.fail("products:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      (parsed["products"]?.try(&.as_a?) || [] of JSON::Any).each do |p|
        id = p["id"]?.try(&.to_s) || "?"
        name = p["name"]?.try(&.as_s?) || "—"
        price = p["price"]?.try(&.to_s) || ""
        line = "#{id}\t#{name}"
        line += "\t#{price}" unless price.empty?
        output.puts line
      end

      if meta = parsed["meta"]?
        output.puts ""
        output.puts "#{meta["total_count"]?} products — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "products:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("products:get", description: "Show a single product by ID")]
  class ProductsGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsGetCommand.add_json_option(self)
      self.argument("id", :required, "product ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/products/#{URI.encode_path(id)}")
      return RightDesk.fail("products:get", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      p = JSON.parse(resp.body)["product"]?
      unless p
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", p["id"]?)
      show.call("name", p["name"]?)
      show.call("code", p["code"]?)
      show.call("category", p["category"]?)
      show.call("price", p["price"]?)
      show.call("currency", p["currency"]?)
      show.call("tax", p["tax"]?)
      show.call("unit", p["unit"]?)
      show.call("billing_frequency", p["billing_frequency"]?)
      show.call("billing_cycles", p["billing_cycles"]?)
      show.call("active", p["active"]?)
      show.call("visible_to", p["visible_to"]?)
      show.call("owner_id", p["owner_id"]?)
      show.call("external_id", p["external_record_id"]?)
      show.call("description", p["description"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "products:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("products:create", description: "Create a product")]
  class ProductsCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsCreateCommand.add_json_option(self)
      RightDesk.configure_product_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      product = RightDesk.product_body(input)
      unless product.has_key?("name")
        STDERR.puts "products:create failed: --name is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/products", {"product" => product}.to_json)
      return RightDesk.fail("products:create", resp, json?(input)) unless resp.success?
      RightDesk.print_product_result(input, output, resp)
    rescue ex
      STDERR.puts "products:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("products:update", description: "Update a product by ID")]
  class ProductsUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsUpdateCommand.add_json_option(self)
      self.argument("id", :required, "product ID")
      RightDesk.configure_product_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      product = RightDesk.product_body(input)
      if product.empty?
        STDERR.puts "products:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/products/#{URI.encode_path(id)}", {"product" => product}.to_json)
      return RightDesk.fail("products:update", resp, json?(input)) unless resp.success?
      RightDesk.print_product_result(input, output, resp)
    rescue ex
      STDERR.puts "products:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("products:activate", description: "Activate a product by ID")]
  class ProductsActivateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsActivateCommand.add_json_option(self)
      self.argument("id", :required, "product ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.patch("/api/v1/products/#{URI.encode_path(id)}/activate")
      return RightDesk.fail("products:activate", resp, json?(input)) unless resp.success?
      RightDesk.print_product_result(input, output, resp)
    rescue ex
      STDERR.puts "products:activate failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("products:deactivate", description: "Deactivate a product by ID")]
  class ProductsDeactivateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsDeactivateCommand.add_json_option(self)
      self.argument("id", :required, "product ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.patch("/api/v1/products/#{URI.encode_path(id)}/deactivate")
      return RightDesk.fail("products:deactivate", resp, json?(input)) unless resp.success?
      RightDesk.print_product_result(input, output, resp)
    rescue ex
      STDERR.puts "products:deactivate failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("products:delete", description: "Delete a product by ID (requires --yes)")]
  class ProductsDeleteCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ProductsDeleteCommand.add_json_option(self)
      self.argument("id", :required, "product ID")
      self.option("yes", "y", ACON::Input::Option::Value[:none], "Confirm deletion (required)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      unless input.option("yes", Bool)
        STDERR.puts "products:delete failed: refusing to delete without --yes"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.delete("/api/v1/products/#{URI.encode_path(id)}")
      return RightDesk.fail("products:delete", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts({"id" => id, "deleted" => true}.to_json)
      else
        output.puts "deleted #{id}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "products:delete failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # ----- contacts writes (list/get/search already exist above) -----

  # Build a contact attribute hash from the set --flags (only provided fields).
  def self.contact_body(input : ACON::Input::Interface) : Hash(String, String)
    mapping = {
      "first-name"         => "first_name",
      "last-name"          => "last_name",
      "email"              => "email",
      "phone"              => "phone",
      "note"               => "note",
      "company-id"         => "company_id",
      "line-id"            => "line_id",
      "line-user-id"       => "line_user_id",
      "whatsapp-number"    => "whatsapp_number",
      "linkedin-profile"   => "linkedin_profile",
      "alternative-emails" => "alternative_emails",
    }
    contact = Hash(String, String).new
    mapping.each do |opt, field|
      if value = input.option(opt).to_s.presence
        contact[field] = value
      end
    end
    contact
  end

  def self.configure_contact_options(cmd : ACON::Command) : Nil
    cmd.option("first-name", nil, ACON::Input::Option::Value[:required], "First name")
    cmd.option("last-name", nil, ACON::Input::Option::Value[:required], "Last name")
    cmd.option("email", nil, ACON::Input::Option::Value[:required], "Email")
    cmd.option("phone", nil, ACON::Input::Option::Value[:required], "Phone")
    cmd.option("note", nil, ACON::Input::Option::Value[:required], "Note")
    cmd.option("company-id", nil, ACON::Input::Option::Value[:required], "Company ID")
    cmd.option("line-id", nil, ACON::Input::Option::Value[:required], "LINE ID")
    cmd.option("line-user-id", nil, ACON::Input::Option::Value[:required], "LINE user ID")
    cmd.option("whatsapp-number", nil, ACON::Input::Option::Value[:required], "WhatsApp number")
    cmd.option("linkedin-profile", nil, ACON::Input::Option::Value[:required], "LinkedIn profile")
    cmd.option("alternative-emails", nil, ACON::Input::Option::Value[:required], "Alternative emails")
  end

  def self.print_contact_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      c = JSON.parse(resp.body)["contact"]?
      if c
        name = "#{c["first_name"]?.try(&.as_s?)} #{c["last_name"]?.try(&.as_s?)}".strip
        output.puts "#{c["id"]?}\t#{name}"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("contacts:create", description: "Create a contact")]
  class ContactsCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsCreateCommand.add_json_option(self)
      RightDesk.configure_contact_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      contact = RightDesk.contact_body(input)
      unless contact.has_key?("email")
        STDERR.puts "contacts:create failed: --email is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/contacts", {"contact" => contact}.to_json)
      return RightDesk.fail("contacts:create", resp, json?(input)) unless resp.success?
      RightDesk.print_contact_result(input, output, resp)
    rescue ex
      STDERR.puts "contacts:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:update", description: "Update a contact by ID")]
  class ContactsUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsUpdateCommand.add_json_option(self)
      self.argument("id", :required, "contact ID")
      RightDesk.configure_contact_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      contact = RightDesk.contact_body(input)
      if contact.empty?
        STDERR.puts "contacts:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/contacts/#{URI.encode_path(id)}", {"contact" => contact}.to_json)
      return RightDesk.fail("contacts:update", resp, json?(input)) unless resp.success?
      RightDesk.print_contact_result(input, output, resp)
    rescue ex
      STDERR.puts "contacts:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("contacts:merge", description: "Merge a duplicate contact into a primary (requires --yes)")]
  class ContactsMergeCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ContactsMergeCommand.add_json_option(self)
      self.argument("id", :required, "primary (surviving) contact ID")
      self.option("duplicate", nil, ACON::Input::Option::Value[:required], "duplicate contact ID to absorb (required)")
      self.option("yes", "y", ACON::Input::Option::Value[:none], "Confirm merge (required)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      duplicate = input.option("duplicate").to_s.presence
      unless duplicate
        STDERR.puts "contacts:merge failed: --duplicate ID is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end
      unless input.option("yes", Bool)
        STDERR.puts "contacts:merge failed: refusing to merge without --yes"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/contacts/#{URI.encode_path(id)}/merge", {"duplicate_id" => duplicate}.to_json)
      return RightDesk.fail("contacts:merge", resp, json?(input)) unless resp.success?
      RightDesk.print_contact_result(input, output, resp)
    rescue ex
      STDERR.puts "contacts:merge failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # Print a lean timeline feed (`at  type  summary`) or raw JSON under --json.
  def self.print_timeline(output : ACON::Output::Interface, resp : Client::Response, json : Bool) : ACON::Command::Status
    if json
      output.puts resp.body
      return ACON::Command::Status::SUCCESS
    end
    (JSON.parse(resp.body)["events"]?.try(&.as_a?) || [] of JSON::Any).each do |e|
      type = e["type"]?.try(&.as_s?) || "?"
      at = e["at"]?.try(&.as_s?) || ""
      summary = ""
      if data = e["data"]?
        summary = data["subject"]?.try(&.as_s?) || data["content"]?.try(&.as_s?) || ""
      end
      line = "#{at}\t#{type}"
      line += "\t#{summary}" unless summary.empty?
      output.puts line
    end
    ACON::Command::Status::SUCCESS
  end

  # ----- customers -----

  def self.customer_body(input : ACON::Input::Interface) : Hash(String, String)
    mapping = {
      "contact-id"  => "contact_id",
      "company-id"  => "company_id",
      "owner-id"    => "owner_id",
      "title"       => "title",
      "value"       => "value",
      "currency"    => "currency",
      "became-date" => "became_customer_date",
      "source"      => "source",
      "visible-to"  => "visible_to",
      "status"      => "status",
      "description" => "description",
      "external-id" => "external_record_id",
    }
    customer = Hash(String, String).new
    mapping.each do |opt, field|
      if value = input.option(opt).to_s.presence
        customer[field] = value
      end
    end
    customer
  end

  def self.configure_customer_options(cmd : ACON::Command) : Nil
    cmd.option("title", nil, ACON::Input::Option::Value[:required], "Customer title")
    cmd.option("contact-id", nil, ACON::Input::Option::Value[:required], "Contact ID")
    cmd.option("company-id", nil, ACON::Input::Option::Value[:required], "Company ID")
    cmd.option("owner-id", nil, ACON::Input::Option::Value[:required], "Owner user ID")
    cmd.option("value", nil, ACON::Input::Option::Value[:required], "Deal value")
    cmd.option("currency", nil, ACON::Input::Option::Value[:required], "Currency")
    cmd.option("became-date", nil, ACON::Input::Option::Value[:required], "Became-customer date (YYYY-MM-DD)")
    cmd.option("source", nil, ACON::Input::Option::Value[:required], "Source")
    cmd.option("visible-to", nil, ACON::Input::Option::Value[:required], "owner, team, or everyone")
    cmd.option("status", nil, ACON::Input::Option::Value[:required], "active, inactive, or converted")
    cmd.option("description", nil, ACON::Input::Option::Value[:required], "Description")
    cmd.option("external-id", nil, ACON::Input::Option::Value[:required], "Idempotency key (external_record_id)")
  end

  def self.print_customer_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      c = JSON.parse(resp.body)["customer"]?
      if c
        output.puts "#{c["id"]?}\t#{c["title"]?.try(&.as_s?)}"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("customers:list", description: "List customers (newest first)")]
  class CustomersListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CustomersListCommand.add_json_option(self)
      self
        .option("status", nil, ACON::Input::Option::Value[:required], "Filter by status")
        .option("owner", nil, ACON::Input::Option::Value[:required], "Filter by owner user ID")
        .option("search", nil, ACON::Input::Option::Value[:required], "Filter by title")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if s = input.option("status").to_s.presence
          form.add("status", s)
        end
        if o = input.option("owner").to_s.presence
          form.add("owner_id", o)
        end
        if s = input.option("search").to_s.presence
          form.add("search", s)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/customers", params)
      return RightDesk.fail("customers:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      (parsed["customers"]?.try(&.as_a?) || [] of JSON::Any).each do |c|
        output.puts "#{c["id"]?}\t#{c["title"]?.try(&.as_s?)}\t#{c["status"]?.try(&.as_s?)}"
      end
      if meta = parsed["meta"]?
        output.puts ""
        output.puts "#{meta["total_count"]?} customers — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "customers:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("customers:get", description: "Show a single customer by ID")]
  class CustomersGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CustomersGetCommand.add_json_option(self)
      self.argument("id", :required, "customer ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/customers/#{URI.encode_path(id)}")
      return RightDesk.fail("customers:get", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      c = JSON.parse(resp.body)["customer"]?
      unless c
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", c["id"]?)
      show.call("title", c["title"]?)
      show.call("status", c["status"]?)
      show.call("value", c["value"]?)
      show.call("currency", c["currency"]?)
      show.call("source", c["source"]?)
      show.call("contact", c["contact_name"]?)
      show.call("company", c["company_name"]?)
      show.call("owner", c["owner_name"]?)
      show.call("external_id", c["external_record_id"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "customers:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("customers:create", description: "Create a customer")]
  class CustomersCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CustomersCreateCommand.add_json_option(self)
      RightDesk.configure_customer_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      customer = RightDesk.customer_body(input)
      unless customer.has_key?("title")
        STDERR.puts "customers:create failed: --title is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/customers", {"customer" => customer}.to_json)
      return RightDesk.fail("customers:create", resp, json?(input)) unless resp.success?
      RightDesk.print_customer_result(input, output, resp)
    rescue ex
      STDERR.puts "customers:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("customers:update", description: "Update a customer by ID")]
  class CustomersUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CustomersUpdateCommand.add_json_option(self)
      self.argument("id", :required, "customer ID")
      RightDesk.configure_customer_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      customer = RightDesk.customer_body(input)
      if customer.empty?
        STDERR.puts "customers:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/customers/#{URI.encode_path(id)}", {"customer" => customer}.to_json)
      return RightDesk.fail("customers:update", resp, json?(input)) unless resp.success?
      RightDesk.print_customer_result(input, output, resp)
    rescue ex
      STDERR.puts "customers:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("customers:timeline", description: "Show a customer's history timeline")]
  class CustomersTimelineCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      CustomersTimelineCommand.add_json_option(self)
      self.argument("id", :required, "customer ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/customers/#{URI.encode_path(id)}/timeline")
      return RightDesk.fail("customers:timeline", resp, json?(input)) unless resp.success?
      RightDesk.print_timeline(output, resp, json?(input))
    rescue ex
      STDERR.puts "customers:timeline failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  # ----- partners -----

  def self.partner_body(input : ACON::Input::Interface) : Hash(String, String)
    mapping = {
      "contact-id"   => "contact_id",
      "company-id"   => "company_id",
      "owner-id"     => "owner_id",
      "title"        => "title",
      "value"        => "value",
      "currency"     => "currency",
      "became-date"  => "became_partner_date",
      "partner-type" => "partner_type",
      "source"       => "source",
      "visible-to"   => "visible_to",
      "status"       => "status",
      "description"  => "description",
      "external-id"  => "external_record_id",
    }
    partner = Hash(String, String).new
    mapping.each do |opt, field|
      if value = input.option(opt).to_s.presence
        partner[field] = value
      end
    end
    partner
  end

  def self.configure_partner_options(cmd : ACON::Command) : Nil
    cmd.option("title", nil, ACON::Input::Option::Value[:required], "Partner title")
    cmd.option("contact-id", nil, ACON::Input::Option::Value[:required], "Contact ID")
    cmd.option("company-id", nil, ACON::Input::Option::Value[:required], "Company ID")
    cmd.option("owner-id", nil, ACON::Input::Option::Value[:required], "Owner user ID")
    cmd.option("value", nil, ACON::Input::Option::Value[:required], "Value")
    cmd.option("currency", nil, ACON::Input::Option::Value[:required], "Currency")
    cmd.option("became-date", nil, ACON::Input::Option::Value[:required], "Became-partner date (YYYY-MM-DD)")
    cmd.option("partner-type", nil, ACON::Input::Option::Value[:required], "reseller, distributor, technology_partner, or referral_partner")
    cmd.option("source", nil, ACON::Input::Option::Value[:required], "Source")
    cmd.option("visible-to", nil, ACON::Input::Option::Value[:required], "owner, team, or everyone")
    cmd.option("status", nil, ACON::Input::Option::Value[:required], "active, inactive, or converted")
    cmd.option("description", nil, ACON::Input::Option::Value[:required], "Description")
    cmd.option("external-id", nil, ACON::Input::Option::Value[:required], "Idempotency key (external_record_id)")
  end

  def self.print_partner_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      p = JSON.parse(resp.body)["partner"]?
      if p
        output.puts "#{p["id"]?}\t#{p["title"]?.try(&.as_s?)} (#{p["partner_type"]?.try(&.as_s?)})"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("partners:list", description: "List partners (newest first)")]
  class PartnersListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PartnersListCommand.add_json_option(self)
      self
        .option("status", nil, ACON::Input::Option::Value[:required], "Filter by status")
        .option("owner", nil, ACON::Input::Option::Value[:required], "Filter by owner user ID")
        .option("partner-type", nil, ACON::Input::Option::Value[:required], "Filter by partner type")
        .option("search", nil, ACON::Input::Option::Value[:required], "Filter by title")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        if s = input.option("status").to_s.presence
          form.add("status", s)
        end
        if o = input.option("owner").to_s.presence
          form.add("owner_id", o)
        end
        if t = input.option("partner-type").to_s.presence
          form.add("partner_type", t)
        end
        if s = input.option("search").to_s.presence
          form.add("search", s)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/partners", params)
      return RightDesk.fail("partners:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      (parsed["partners"]?.try(&.as_a?) || [] of JSON::Any).each do |p|
        output.puts "#{p["id"]?}\t#{p["title"]?.try(&.as_s?)}\t#{p["partner_type"]?.try(&.as_s?)}"
      end
      if meta = parsed["meta"]?
        output.puts ""
        output.puts "#{meta["total_count"]?} partners — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "partners:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("partners:get", description: "Show a single partner by ID")]
  class PartnersGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PartnersGetCommand.add_json_option(self)
      self.argument("id", :required, "partner ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/partners/#{URI.encode_path(id)}")
      return RightDesk.fail("partners:get", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      p = JSON.parse(resp.body)["partner"]?
      unless p
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", p["id"]?)
      show.call("title", p["title"]?)
      show.call("partner_type", p["partner_type"]?)
      show.call("status", p["status"]?)
      show.call("value", p["value"]?)
      show.call("currency", p["currency"]?)
      show.call("source", p["source"]?)
      show.call("contact", p["contact_name"]?)
      show.call("company", p["company_name"]?)
      show.call("owner", p["owner_name"]?)
      show.call("external_id", p["external_record_id"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "partners:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("partners:create", description: "Create a partner")]
  class PartnersCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PartnersCreateCommand.add_json_option(self)
      RightDesk.configure_partner_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      partner = RightDesk.partner_body(input)
      unless partner.has_key?("title")
        STDERR.puts "partners:create failed: --title is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/partners", {"partner" => partner}.to_json)
      return RightDesk.fail("partners:create", resp, json?(input)) unless resp.success?
      RightDesk.print_partner_result(input, output, resp)
    rescue ex
      STDERR.puts "partners:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("partners:update", description: "Update a partner by ID")]
  class PartnersUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PartnersUpdateCommand.add_json_option(self)
      self.argument("id", :required, "partner ID")
      RightDesk.configure_partner_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      partner = RightDesk.partner_body(input)
      if partner.empty?
        STDERR.puts "partners:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/partners/#{URI.encode_path(id)}", {"partner" => partner}.to_json)
      return RightDesk.fail("partners:update", resp, json?(input)) unless resp.success?
      RightDesk.print_partner_result(input, output, resp)
    rescue ex
      STDERR.puts "partners:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("partners:timeline", description: "Show a partner's history timeline")]
  class PartnersTimelineCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      PartnersTimelineCommand.add_json_option(self)
      self.argument("id", :required, "partner ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/partners/#{URI.encode_path(id)}/timeline")
      return RightDesk.fail("partners:timeline", resp, json?(input)) unless resp.success?
      RightDesk.print_timeline(output, resp, json?(input))
    rescue ex
      STDERR.puts "partners:timeline failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end
end
