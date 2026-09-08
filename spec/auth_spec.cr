require "./spec_helper"

# Isolate HOME so specs never touch the real ~/.netrc. BASE_URL (and thus
# Auth.host) is fixed at load to the default app.rightdesk.com host.
TMP_HOME = File.tempname("rightdesk-home")
Dir.mkdir_p(TMP_HOME)
ENV["HOME"] = TMP_HOME
ENV.delete("RIGHTDESK_TOKEN")

private def netrc_file
  File.join(TMP_HOME, ".netrc")
end

describe RightDesk::Auth do
  after_each do
    File.delete(netrc_file) if File.exists?(netrc_file)
    ENV.delete("RIGHTDESK_TOKEN")
  end

  it "stores and reads a token round-trip" do
    RightDesk::Auth.store("secret-abc")
    RightDesk::Auth.token.should eq("secret-abc")
  end

  it "overwrites an existing token on re-login" do
    RightDesk::Auth.store("first")
    RightDesk::Auth.store("second")
    RightDesk::Auth.token.should eq("second")
  end

  it "clears the token" do
    RightDesk::Auth.store("secret-abc")
    RightDesk::Auth.clear
    RightDesk::Auth.token.should be_nil
  end

  it "preserves other machines' entries when storing" do
    File.write(netrc_file, "machine github.com\n  login me\n  password gh-token\n")
    RightDesk::Auth.store("rd-token")
    content = File.read(netrc_file)
    content.should contain("github.com")
    content.should contain("gh-token")
    content.should contain("rd-token")
  end

  it "prefers the RIGHTDESK_TOKEN env override over ~/.netrc" do
    RightDesk::Auth.store("netrc-token")
    ENV["RIGHTDESK_TOKEN"] = "env-token"
    RightDesk::Auth.token.should eq("env-token")
  end

  it "writes the netrc file with 0600 permissions" do
    RightDesk::Auth.store("secret-abc")
    File.info(netrc_file).permissions.should eq(File::Permissions.new(0o600))
  end
end
