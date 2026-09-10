require "athena-console"
require "json"
require "uri"
require "colorize"
require "../client"

module RightDesk
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
end
