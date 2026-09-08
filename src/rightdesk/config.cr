module RightDesk
  # API host. Override for self-hosted or local dev, e.g.
  #   RIGHTDESK_URL=http://localhost:3000 rightdesk whoami
  BASE_URL = ENV["RIGHTDESK_URL"]? || "https://app.rightdesk.com"
end
