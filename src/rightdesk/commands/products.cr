require "athena-console"
require "json"
require "uri"
require "../client"

module RightDesk
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
end
