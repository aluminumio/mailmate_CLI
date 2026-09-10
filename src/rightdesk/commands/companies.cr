require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
end
