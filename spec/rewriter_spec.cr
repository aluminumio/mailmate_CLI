require "./spec_helper"

# The ARGV rewriter turns the gh-style `rd <noun> <verb>` grammar into the
# colon form athena-console resolves natively, without touching flags or
# unknown/bare/colon input.
describe RightDesk::CLI do
  describe ".join_noun_verb" do
    {
      ["deals", "list"]              => ["deals:list"],
      ["deals", "get", "5"]          => ["deals:get", "5"],
      ["contacts", "search", "acme"] => ["contacts:search", "acme"],
      ["companies", "list"]          => ["companies:list"],
      ["companies", "get", "5"]      => ["companies:get", "5"],
      ["companies", "create", "--name", "Acme"] => ["companies:create", "--name", "Acme"],
      ["pipelines", "create", "--name", "Sales"] => ["pipelines:create", "--name", "Sales"],
      ["pipelines", "delete", "5", "--yes"] => ["pipelines:delete", "5", "--yes"],
      ["stages", "reorder", "--pipeline", "2"] => ["stages:reorder", "--pipeline", "2"],
      ["stages", "delete", "7", "--pipeline", "2", "--yes"] => ["stages:delete", "7", "--pipeline", "2", "--yes"],
      ["products", "get", "5"] => ["products:get", "5"],
      ["products", "activate", "5"] => ["products:activate", "5"],
      ["products", "deactivate", "5"] => ["products:deactivate", "5"],
      ["contacts", "merge", "5", "--duplicate", "6"] => ["contacts:merge", "5", "--duplicate", "6"],
      ["contacts", "create", "--email", "a@b.co"] => ["contacts:create", "--email", "a@b.co"],
      ["customers", "timeline", "5"] => ["customers:timeline", "5"],
      ["partners", "create", "--title", "Acme"] => ["partners:create", "--title", "Acme"],
      ["deals", "list", "--json"]    => ["deals:list", "--json"],
      ["deals", "list", "--status", "open"] => ["deals:list", "--status", "open"],
      ["deals"]                      => ["deals"],          # bare noun → namespace listing
      ["deals", "bogus"]             => ["deals", "bogus"], # unknown verb untouched
      ["deals:get", "5"]             => ["deals:get", "5"], # colon form passes through
      ["whoami"]                     => ["whoami"],
      ["--version"]                  => ["--version"],
      [] of String                   => [] of String,
    }.each do |input, expected|
      it "rewrites #{input.inspect}" do
        RightDesk::CLI.join_noun_verb(input).should eq(expected)
      end
    end
  end

  describe ".extract_global_flags" do
    it "pulls out --host value and leaves the rest" do
      remaining = RightDesk::CLI.extract_global_flags(["deals", "list", "--host", "http://localhost:3000"])
      remaining.should eq(["deals", "list"])
      RightDesk::Config.base_url.should eq("http://localhost:3000")
    ensure
      RightDesk::Config.host_override = nil
    end

    it "supports --host=value form" do
      remaining = RightDesk::CLI.extract_global_flags(["--host=example.test", "whoami"])
      remaining.should eq(["whoami"])
      RightDesk::Config.base_url.should eq("https://example.test")
    ensure
      RightDesk::Config.host_override = nil
    end
  end
end
