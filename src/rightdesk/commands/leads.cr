require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
  def self.lead_body(input : ACON::Input::Interface) : Hash(String, String)
    mapping = {
      "contact-id"          => "contact_id",
      "company-id"          => "company_id",
      "owner-id"            => "owner_id",
      "referral-partner-id" => "referral_partner_id",
      "title"               => "title",
      "value"               => "value",
      "currency"            => "currency",
      "expected-close-date" => "expected_close_date",
      "source"              => "source",
      "visible-to"          => "visible_to",
      "status"              => "status",
      "description"         => "description",
      "pipeline-id"         => "pipeline_id",
      "stage-id"            => "stage_id",
      "external-id"         => "external_record_id",
    }
    lead = Hash(String, String).new
    mapping.each do |opt, field|
      if value = input.option(opt).to_s.presence
        lead[field] = value
      end
    end
    lead
  end

  def self.configure_lead_options(cmd : ACON::Command) : Nil
    cmd.option("title", nil, ACON::Input::Option::Value[:required], "Lead title")
    cmd.option("contact-id", nil, ACON::Input::Option::Value[:required], "Contact ID")
    cmd.option("company-id", nil, ACON::Input::Option::Value[:required], "Company ID")
    cmd.option("owner-id", nil, ACON::Input::Option::Value[:required], "Owner user ID")
    cmd.option("referral-partner-id", nil, ACON::Input::Option::Value[:required], "Referral partner ID")
    cmd.option("value", nil, ACON::Input::Option::Value[:required], "Value")
    cmd.option("currency", nil, ACON::Input::Option::Value[:required], "Currency")
    cmd.option("expected-close-date", nil, ACON::Input::Option::Value[:required], "Expected close date (YYYY-MM-DD)")
    cmd.option("source", nil, ACON::Input::Option::Value[:required], "Source")
    cmd.option("visible-to", nil, ACON::Input::Option::Value[:required], "owner, team, or everyone")
    cmd.option("status", nil, ACON::Input::Option::Value[:required], "new, contacted, qualified, disqualified, converted")
    cmd.option("description", nil, ACON::Input::Option::Value[:required], "Description")
    cmd.option("pipeline-id", nil, ACON::Input::Option::Value[:required], "Pipeline ID")
    cmd.option("stage-id", nil, ACON::Input::Option::Value[:required], "Stage ID")
    cmd.option("external-id", nil, ACON::Input::Option::Value[:required], "Idempotency key (external_record_id)")
  end

  def self.print_lead_result(input : ACON::Input::Interface, output : ACON::Output::Interface, resp : Client::Response) : ACON::Command::Status
    if input.option("json", Bool)
      output.puts resp.body
    else
      l = JSON.parse(resp.body)["lead"]?
      if l
        output.puts "#{l["id"]?}\t#{l["title"]?.try(&.as_s?)} (#{l["status"]?.try(&.as_s?)})"
      else
        output.puts resp.body
      end
    end
    ACON::Command::Status::SUCCESS
  end

  @[ACONA::AsCommand("leads:list", description: "List leads (newest first)")]
  class LeadsListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsListCommand.add_json_option(self)
      self
        .option("status", nil, ACON::Input::Option::Value[:required], "Filter by status")
        .option("owner", nil, ACON::Input::Option::Value[:required], "Filter by owner user ID")
        .option("source", nil, ACON::Input::Option::Value[:required], "Filter by source")
        .option("pipeline", nil, ACON::Input::Option::Value[:required], "Filter by pipeline ID")
        .option("stage", nil, ACON::Input::Option::Value[:required], "Filter by stage ID")
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
        if s = input.option("source").to_s.presence
          form.add("source", s)
        end
        if p = input.option("pipeline").to_s.presence
          form.add("pipeline_id", p)
        end
        if s = input.option("stage").to_s.presence
          form.add("stage_id", s)
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/leads", params)
      return RightDesk.fail("leads:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      (parsed["leads"]?.try(&.as_a?) || [] of JSON::Any).each do |l|
        output.puts "#{l["id"]?}\t#{l["title"]?.try(&.as_s?)}\t#{l["status"]?.try(&.as_s?)}"
      end
      if meta = parsed["meta"]?
        output.puts ""
        output.puts "#{meta["total_count"]?} leads — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "leads:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:get", description: "Show a single lead by ID")]
  class LeadsGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsGetCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/leads/#{URI.encode_path(id)}")
      return RightDesk.fail("leads:get", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      l = JSON.parse(resp.body)["lead"]?
      unless l
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", l["id"]?)
      show.call("title", l["title"]?)
      show.call("status", l["status"]?)
      show.call("value", l["value"]?)
      show.call("currency", l["currency"]?)
      show.call("source", l["source"]?)
      show.call("contact", l["contact_name"]?)
      show.call("company", l["company_name"]?)
      show.call("pipeline", l["pipeline_name"]?)
      show.call("stage", l["stage_name"]?)
      show.call("owner", l["owner_name"]?)
      show.call("disqualified_reason", l["disqualified_reason"]?)
      show.call("converted_deal_id", l["converted_deal_id"]?)
      show.call("external_id", l["external_record_id"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "leads:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:create", description: "Create a lead")]
  class LeadsCreateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsCreateCommand.add_json_option(self)
      RightDesk.configure_lead_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      lead = RightDesk.lead_body(input)
      unless lead.has_key?("title")
        STDERR.puts "leads:create failed: --title is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.post("/api/v1/leads", {"lead" => lead}.to_json)
      return RightDesk.fail("leads:create", resp, json?(input)) unless resp.success?
      RightDesk.print_lead_result(input, output, resp)
    rescue ex
      STDERR.puts "leads:create failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:update", description: "Update a lead by ID")]
  class LeadsUpdateCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsUpdateCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
      RightDesk.configure_lead_options(self)
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      lead = RightDesk.lead_body(input)
      if lead.empty?
        STDERR.puts "leads:update failed: provide at least one field to update"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.patch("/api/v1/leads/#{URI.encode_path(id)}", {"lead" => lead}.to_json)
      return RightDesk.fail("leads:update", resp, json?(input)) unless resp.success?
      RightDesk.print_lead_result(input, output, resp)
    rescue ex
      STDERR.puts "leads:update failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:delete", description: "Delete a lead by ID (requires --yes)")]
  class LeadsDeleteCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsDeleteCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
      self.option("yes", "y", ACON::Input::Option::Value[:none], "Confirm deletion (required)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      unless input.option("yes", Bool)
        STDERR.puts "leads:delete failed: refusing to delete without --yes"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      resp = RightDesk::Client.delete("/api/v1/leads/#{URI.encode_path(id)}")
      return RightDesk.fail("leads:delete", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts({"id" => id, "deleted" => true}.to_json)
      else
        output.puts "deleted #{id}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "leads:delete failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:move", description: "Move a lead to a stage (or --unassigned)")]
  class LeadsMoveCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsMoveCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
      self.option("stage", nil, ACON::Input::Option::Value[:required], "Target stage ID")
      self.option("unassigned", nil, ACON::Input::Option::Value[:none], "Remove the lead from its pipeline")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      stage = input.option("stage").to_s.presence
      if stage.nil? && !input.option("unassigned", Bool)
        STDERR.puts "leads:move failed: provide --stage ID or --unassigned"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      body = {"stage_id" => (input.option("unassigned", Bool) ? "unassigned" : stage)}
      resp = RightDesk::Client.patch("/api/v1/leads/#{URI.encode_path(id)}/move", body.to_json)
      return RightDesk.fail("leads:move", resp, json?(input)) unless resp.success?
      RightDesk.print_lead_result(input, output, resp)
    rescue ex
      STDERR.puts "leads:move failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:qualify", description: "Mark a lead qualified")]
  class LeadsQualifyCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsQualifyCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.patch("/api/v1/leads/#{URI.encode_path(id)}/qualify")
      return RightDesk.fail("leads:qualify", resp, json?(input)) unless resp.success?
      RightDesk.print_lead_result(input, output, resp)
    rescue ex
      STDERR.puts "leads:qualify failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:disqualify", description: "Mark a lead disqualified")]
  class LeadsDisqualifyCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsDisqualifyCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
      self.option("reason", nil, ACON::Input::Option::Value[:required], "Disqualification reason")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      body = Hash(String, String).new
      if reason = input.option("reason").to_s.presence
        body["reason"] = reason
      end
      resp = RightDesk::Client.patch("/api/v1/leads/#{URI.encode_path(id)}/disqualify", body.to_json)
      return RightDesk.fail("leads:disqualify", resp, json?(input)) unless resp.success?
      RightDesk.print_lead_result(input, output, resp)
    rescue ex
      STDERR.puts "leads:disqualify failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("leads:convert", description: "Convert a lead to a deal, customer, or partner (requires --yes)")]
  class LeadsConvertCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      LeadsConvertCommand.add_json_option(self)
      self.argument("id", :required, "lead ID")
      self.option("to", nil, ACON::Input::Option::Value[:required], "Target: deal, customer, or partner (required)")
      self.option("pipeline", nil, ACON::Input::Option::Value[:required], "Deal pipeline ID (for --to deal)")
      self.option("yes", "y", ACON::Input::Option::Value[:none], "Confirm conversion (required)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      target = input.option("to").to_s.presence
      unless target
        STDERR.puts "leads:convert failed: --to deal|customer|partner is required"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end
      unless input.option("yes", Bool)
        STDERR.puts "leads:convert failed: refusing to convert without --yes"
        RightDesk.exit_code = 2
        return ACON::Command::Status::FAILURE
      end

      body = Hash(String, String).new
      body["to"] = target
      if pipeline = input.option("pipeline").to_s.presence
        body["pipeline_id"] = pipeline
      end

      resp = RightDesk::Client.post("/api/v1/leads/#{URI.encode_path(id)}/convert", body.to_json)
      return RightDesk.fail("leads:convert", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
      else
        parsed = JSON.parse(resp.body)
        record = parsed[target]?
        if record
          output.puts "#{target} #{record["id"]?}\t#{record["title"]?.try(&.as_s?)}"
        else
          output.puts resp.body
        end
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "leads:convert failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end
end
