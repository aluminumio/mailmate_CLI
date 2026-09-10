require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
end
