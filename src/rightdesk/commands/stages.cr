require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
end
