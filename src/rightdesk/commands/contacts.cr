require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
end
