require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
