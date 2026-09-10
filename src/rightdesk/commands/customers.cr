require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
end
