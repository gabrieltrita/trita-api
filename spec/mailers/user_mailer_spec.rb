require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  let(:user) { create(:user) }
  let(:frontend) { ENV.fetch("FRONTEND_URL", "http://localhost:5173") }

  def text_of(mail)
    mail.text_part.body.decoded
  end

  def token_from(mail, path)
    CGI.unescape(text_of(mail)[/#{Regexp.escape("#{frontend}#{path}?token=")}(\S+)/, 1])
  end

  describe "sender" do
    around do |example|
      original = ENV.delete("MAILER_FROM")
      example.run
    ensure
      original ? ENV["MAILER_FROM"] = original : ENV.delete("MAILER_FROM")
    end

    it "defaults to no-reply at the app domain" do
      app = Rails.configuration.x.app
      expect(described_class.welcome(user)[:from].value).to eq("#{app.name} <no-reply@#{app.domain}>")
    end

    it "uses MAILER_FROM when set" do
      ENV["MAILER_FROM"] = "Support <support@example.com>"
      expect(described_class.welcome(user)[:from].value).to eq("Support <support@example.com>")
    end
  end

  it "sends the confirmation link with a token that confirms this user" do
    pending_user = create(:user, :unconfirmed)
    mail = described_class.confirmation_instructions(pending_user)

    expect(mail.to).to eq([ pending_user.email ])
    expect(mail.subject).to eq("Confirm your email")
    expect(User.find_by_token_for(:email_confirmation, token_from(mail, "/confirm-email"))).to eq(pending_user)
  end

  it "tells the owner someone tried to sign up with their email" do
    mail = described_class.registration_attempt(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Sign-up attempt with your email")
    expect(text_of(mail)).to include("#{frontend}/login", "#{frontend}/forgot-password")
  end

  it "welcomes a confirmed user" do
    mail = described_class.welcome(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Welcome to #{Rails.configuration.x.app.name}!")
    expect(text_of(mail)).to include("#{frontend}/login")
  end

  it "sends the reset link with a token that resets this user's password" do
    mail = described_class.password_reset(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Reset your password")
    expect(User.find_by_token_for(:password_reset, token_from(mail, "/reset-password"))).to eq(user)
  end

  it "warns the owner that the password changed" do
    mail = described_class.password_changed(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Your password was changed")
    expect(text_of(mail)).to include("#{frontend}/forgot-password")
  end

  it "sends the new address a token that confirms the email change" do
    user.update!(unconfirmed_email: "new-address@example.com")
    mail = described_class.email_change_confirmation(user)

    expect(mail.to).to eq([ "new-address@example.com" ])
    expect(mail.subject).to eq("Confirm your new email")
    expect(User.find_by_token_for(:email_change, token_from(mail, "/confirm-email-change"))).to eq(user)
  end

  it "warns the current address about the email change" do
    user.update!(unconfirmed_email: "new-address@example.com")
    mail = described_class.email_change_requested(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Email change requested")
    expect(text_of(mail)).to include("#{frontend}/forgot-password")
  end

  it "tells the owner the account was locked" do
    5.times { user.register_failed_login! }
    mail = described_class.account_locked(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Your account was temporarily locked")
    expect(text_of(mail)).to include("#{frontend}/forgot-password")
  end

  it "tells the owner 2FA was disabled" do
    mail = described_class.two_factor_disabled(user)

    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to eq("Two-factor authentication disabled")
    expect(text_of(mail)).to include("#{frontend}/forgot-password")
  end
end
