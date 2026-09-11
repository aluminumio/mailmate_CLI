require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
  @[ACONA::AsCommand("activities:list", description: "List activities (by due date)")]
  class ActivitiesListCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ActivitiesListCommand.add_json_option(self)
      self
        .option("done", nil, ACON::Input::Option::Value[:required], "Filter by done state: true or false")
        .option("type", nil, ACON::Input::Option::Value[:required], "Filter by activity type")
        .option("assigned-to", nil, ACON::Input::Option::Value[:required], "Filter by assignee user ID")
        .option("deal", nil, ACON::Input::Option::Value[:required], "Filter by deal ID")
        .option("lead", nil, ACON::Input::Option::Value[:required], "Filter by lead ID")
        .option("contact", nil, ACON::Input::Option::Value[:required], "Filter by contact ID")
        .option("company", nil, ACON::Input::Option::Value[:required], "Filter by company ID")
        .option("customer", nil, ACON::Input::Option::Value[:required], "Filter by customer ID")
        .option("partner", nil, ACON::Input::Option::Value[:required], "Filter by partner ID")
        .option("due-before", nil, ACON::Input::Option::Value[:required], "Due before date (YYYY-MM-DD)")
        .option("due-after", nil, ACON::Input::Option::Value[:required], "Due after date (YYYY-MM-DD)")
        .option("page", nil, ACON::Input::Option::Value[:required], "Page number (default 1)")
        .option("limit", nil, ACON::Input::Option::Value[:required], "Results per page (max 100)")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      params = URI::Params.build do |form|
        {
          "done"        => "done",
          "type"        => "activity_type",
          "assigned-to" => "assigned_to_id",
          "deal"        => "deal_id",
          "lead"        => "lead_id",
          "contact"     => "contact_id",
          "company"     => "company_id",
          "customer"    => "customer_id",
          "partner"     => "partner_id",
          "due-before"  => "due_before",
          "due-after"   => "due_after",
        }.each do |opt, param|
          if v = input.option(opt).to_s.presence
            form.add(param, v)
          end
        end
        if p = input.option("page").to_s.presence
          form.add("page", p)
        end
        if l = input.option("limit").to_s.presence
          form.add("per_page", l)
        end
      end

      resp = RightDesk::Client.get("/api/v1/activities", params)
      return RightDesk.fail("activities:list", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      parsed = JSON.parse(resp.body)
      (parsed["activities"]?.try(&.as_a?) || [] of JSON::Any).each do |a|
        id = a["id"]?.try(&.to_s) || "?"
        subject = a["subject"]?.try(&.as_s?) || "—"
        type = a["activity_type"]?.try(&.as_s?) || ""
        mark = a["done"]?.try(&.as_bool?) ? "✓" : "○"
        link = a["primary_link_name"]?.try(&.as_s?) || ""
        line = "#{id}\t#{mark} #{subject} (#{type})"
        line += "\t→ #{link}" unless link.empty?
        output.puts line
      end

      if meta = parsed["meta"]?
        output.puts ""
        output.puts "#{meta["total_count"]?} activities — page #{meta["current_page"]?}/#{meta["total_pages"]?}"
      end
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "activities:list failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end

  @[ACONA::AsCommand("activities:get", description: "Show a single activity by ID")]
  class ActivitiesGetCommand < ACON::Command
    include JSONOption

    protected def configure : Nil
      ActivitiesGetCommand.add_json_option(self)
      self.argument("id", :required, "activity ID")
    end

    protected def execute(input : ACON::Input::Interface, output : ACON::Output::Interface) : ACON::Command::Status
      id = input.argument("id").to_s
      resp = RightDesk::Client.get("/api/v1/activities/#{URI.encode_path(id)}")
      return RightDesk.fail("activities:get", resp, json?(input)) unless resp.success?

      if json?(input)
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end

      a = JSON.parse(resp.body)["activity"]?
      unless a
        output.puts resp.body
        return ACON::Command::Status::SUCCESS
      end
      show = ->(label : String, value : JSON::Any?) {
        v = value.try(&.to_s)
        output.puts "#{label}: #{v}" if v && !v.empty? && v != "null"
      }
      show.call("id", a["id"]?)
      show.call("subject", a["subject"]?)
      show.call("type", a["activity_type"]?)
      show.call("done", a["done"]?)
      show.call("due_date", a["due_date"]?)
      show.call("overdue", a["overdue"]?)
      show.call("duration_minutes", a["duration_minutes"]?)
      show.call("logged_minutes", a["total_logged_minutes"]?)
      show.call("assigned_to", a["assigned_to_name"]?)
      show.call("linked_to", a["primary_link_type"]?)
      show.call("linked_name", a["primary_link_name"]?)
      show.call("description", a["description"]?)
      ACON::Command::Status::SUCCESS
    rescue ex
      STDERR.puts "activities:get failed: #{ex.message}"
      RightDesk.exit_code = 1
      ACON::Command::Status::FAILURE
    end
  end
end
