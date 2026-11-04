require "rails_helper"

RSpec.describe User do
  def raw_row(user, columns)
    User.connection.select_one("SELECT #{columns} FROM users WHERE id = #{User.connection.quote(user.id)}")
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to define_enum_for(:role).with_values(user: 0, admin: 1) }

    it "requires a password when there is no identity" do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
      expect(user.errors.details[:password]).to include(error: :blank)
    end

    it "accepts a missing password when an identity is present" do
      expect(build(:user, :passwordless)).to be_valid
    end

    it "rejects a password confirmation mismatch" do
      user = build(:user, password: "Senha@123", password_confirmation: "Outra@123")
      expect(user).not_to be_valid
      expect(user.errors.details[:password_confirmation]).to include(error: :confirmation, attribute: "Password")
    end

    it "requires a strong password" do
      user = build(:user, password: "fraquinha")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "rejects duplicate emails (case insensitive)" do
      create(:user, email: "dup@example.com")
      expect(build(:user, email: "DUP@example.com")).not_to be_valid
    end
  end

  describe "encryption" do
    let!(:user) { create(:user, :with_2fa, email: "secreto@example.com", first_name: "Maria", phone: "+5511988887777") }

    it "does not store personal data in plain text" do
      raw = raw_row(user, "email, first_name, last_name, phone, otp_secret")

      expect(raw["email"]).not_to include("secreto")
      expect(raw["first_name"]).not_to include("Maria")
      expect(raw["phone"]).not_to include("5511988887777")
      expect(raw["otp_secret"]).not_to include(user.otp_secret)
    end

    it "decrypts transparently" do
      reloaded = User.find(user.id)
      expect(reloaded.email).to eq("secreto@example.com")
      expect(reloaded.first_name).to eq("Maria")
    end

    it "allows lookup by email (deterministic encryption)" do
      expect(User.find_by(email: "SECRETO@example.com ")).to eq(user)
    end
  end

  describe "progressive lockout" do
    let(:user) { create(:user) }

    it "locks for 15 minutes on the 5th failure and emails the user" do
      4.times { user.register_failed_login! }
      expect(user).not_to be_access_locked

      expect { user.register_failed_login! }.to have_enqueued_mail(UserMailer, :account_locked)
      expect(user).to be_access_locked
      expect(user.locked_until).to be_within(5.seconds).of(15.minutes.from_now)
    end

    it "doubles the lock on each new failure, up to 24h" do
      5.times { user.register_failed_login! }
      user.register_failed_login!
      expect(user.locked_until).to be_within(5.seconds).of(30.minutes.from_now)

      20.times { user.register_failed_login! }
      expect(user.locked_until).to be_within(5.seconds).of(24.hours.from_now)
    end

    it "unlocks when the password changes" do
      5.times { user.register_failed_login! }
      user.update!(password: "Nova@12345")
      expect(user.reload).not_to be_access_locked
    end
  end

  describe "deactivation" do
    let(:user) { create(:user) }

    it "keeps the data, revokes every session and can be undone" do
      tokens_family = Auth::TokenIssuer.call(user)[:refresh_token]

      user.deactivate!
      expect(user.reload).to be_deactivated
      expect(User.deactivated).to eq([ user ])
      expect(User.not_deactivated).to be_empty
      expect(RefreshToken.find_by_raw_token(tokens_family)).to have_attributes(revoked_reason: "deactivated")

      user.reactivate!
      expect(user.reload).not_to be_deactivated
      expect(User.not_deactivated).to eq([ user ])
    end
  end

  describe "password change" do
    let(:user) { create(:user) }

    it "revokes every session, audits and notifies the user" do
      tokens = tokens_for(user)
      expect {
        user.update!(password: "Nova@12345")
      }.to have_enqueued_mail(UserMailer, :password_changed)

      expect(user.refresh_tokens.active).to be_empty
      expect(RefreshToken.find_by_raw_token(tokens[:refresh_token])).to be_revoked
      expect(AuditLog.where(action: "user.password_changed", target_id: user.id)).to exist
    end
  end

  describe "passwordless accounts" do
    let(:user) { create(:user, :passwordless) }

    it "reports no password and counts the identity as the only login method" do
      expect(user).not_to be_password_set
      expect(user.login_methods_count).to eq(1)
    end

    it "counts the password and every identity as login methods" do
      with_password = create(:user)
      create(:identity, user: with_password)
      expect(with_password).to be_password_set
      expect(with_password.login_methods_count).to eq(2)
    end

    it "does not authenticate with any password" do
      expect(user.authenticate("Senha@123")).to be(false)
      expect(described_class.authenticate_by(email: user.email, password: "Senha@123")).to be_nil
    end

    it "generates a password reset token that stops working once a password is set" do
      token = user.generate_token_for(:password_reset)
      expect(described_class.find_by_token_for(:password_reset, token)).to eq(user)

      user.update!(password: "Nova@12345")
      expect(described_class.find_by_token_for(:password_reset, token)).to be_nil
    end
  end

  describe "#anonymize!" do
    let(:user) { create(:user, :with_2fa, email: "titular@example.com", first_name: "Joana", phone: "+5511911112222") }

    it "removes personal data, keeps encryption and ends sessions" do
      tokens_for(user)
      user.anonymize!
      user.reload

      expect(user).to be_anonymized
      expect(user.email).to eq("anon-#{user.id}@anonymized.invalid")
      expect(user.first_name).to eq("Deleted")
      expect(user.phone).to be_nil
      expect(user).not_to be_two_factor_enabled
      expect(user.refresh_tokens.active).to be_empty
      expect(User.find_by(email: "titular@example.com")).to be_nil
      expect(raw_row(user, "first_name")["first_name"]).not_to include("Deleted")
    end

    it "deletes the linked identities" do
      create(:identity, user: user)
      other = create(:identity)

      user.anonymize!

      expect(user.identities).to be_empty
      expect(Identity.exists?(other.id)).to be(true)
    end

    it "deletes the content listed in PERSONAL_DATA" do
      create_list(:note, 2, user: user)
      other = create(:note)

      user.anonymize!

      expect(user.notes).to be_empty
      expect(Note.exists?(other.id)).to be(true)
    end
  end

  describe "2FA" do
    let(:user) { create(:user) }

    it "enables with a valid code and generates 10 single-use backup codes" do
      user.generate_otp_secret!
      codes = user.enable_two_factor!(otp_code(user))

      expect(user).to be_two_factor_enabled
      expect(codes.size).to eq(10)
      expect(user.verify_second_factor(codes.first)).to be(true)
      expect(user.verify_second_factor(codes.first)).to be(false)
      expect(user.backup_codes_remaining).to eq(9)
    end

    it "rejects the same TOTP code twice (replay)" do
      user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
      code = otp_code(user)

      expect(user.verify_otp(code)).to be(true)
      expect(user.verify_otp(code)).to be(false)
    end

    it "does not store backup codes in plain text" do
      user.generate_otp_secret!
      codes = user.enable_two_factor!(otp_code(user))
      expect(user.otp_backup_code_digests).not_to include(codes.first)
    end
  end

  describe "confirmation" do
    it "keeps the original confirmation time when confirmed again" do
      user = create(:user, confirmed_at: 2.days.ago.change(usec: 0))
      expect { user.confirm! }.not_to change { user.reload.confirmed_at }
    end

    it "refuses to confirm an email change that was never requested" do
      user = create(:user)
      expect { user.confirm_email_change! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "enabling 2FA" do
    it "does nothing before the setup generated a secret" do
      user = create(:user)
      expect(user.enable_two_factor!("123456")).to be_nil
      expect(user.reload).not_to be_two_factor_enabled
    end

    it "does nothing when 2FA is already enabled" do
      user = create(:user, :with_2fa)
      expect { expect(user.enable_two_factor!(otp_code(user))).to be_nil }.not_to change { user.reload.otp_backup_code_digests }
    end
  end
end
