require "rails_helper"

RSpec.describe "Registration and email confirmation", type: :request do
  let(:params) do
    {
      email: "novo@example.com", password: "Senha@123", password_confirmation: "Senha@123",
      first_name: "New", last_name: "User", accept_terms: true, accept_privacy: true
    }
  end

  describe "POST /api/v1/auth/register" do
    it "creates an unconfirmed user account, records consents and sends the confirmation" do
      expect {
        post "/api/v1/auth/register", params: params.merge(role: "admin"), as: :json
      }.to change(User, :count).by(1).and have_enqueued_mail(UserMailer, :confirmation_instructions)

      expect(response).to have_http_status(:accepted)
      expect(json["data"]).not_to have_key("tokens")

      user = User.find_by(email: "novo@example.com")
      expect(user).to be_user
      expect(user).not_to be_confirmed
      expect(Consent.status_for(user).transform_values { |v| v[:granted] }).to eq("terms" => true, "privacy" => true, "marketing" => false)
    end

    it "requires accepting the terms and the privacy policy" do
      post "/api/v1/auth/register", params: params.except(:accept_terms, :accept_privacy), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details").keys).to include("accept_terms", "accept_privacy")
      expect(json.dig("error", "details", "accept_terms", 0, "code")).to eq("required")
    end

    context "email enumeration protection" do
      it "existing confirmed email: same 202 response and the owner gets a notice" do
        create(:user, email: "novo@example.com")

        expect {
          post "/api/v1/auth/register", params: params, as: :json
        }.to have_enqueued_mail(UserMailer, :registration_attempt).and change(User, :count).by(0)

        expect(response).to have_http_status(:accepted)
      end

      it "existing unconfirmed email: resends the confirmation" do
        create(:user, :unconfirmed, email: "novo@example.com")

        expect {
          post "/api/v1/auth/register", params: params, as: :json
        }.to have_enqueued_mail(UserMailer, :confirmation_instructions)
        expect(response).to have_http_status(:accepted)
      end

      it "does not leak 'email already taken' in validation errors" do
        create(:user, email: "novo@example.com")
        post "/api/v1/auth/register", params: params.merge(password: "fraca", password_confirmation: "fraca"), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).not_to have_key("email")
        expect(json.dig("error", "details", "password").map { |e| e["code"] }).to include("too_short", "weak_password")
      end

      context "when another sign-up with the same email commits first" do
        let!(:existing) { create(:user, email: "novo@example.com") }

        before do
          allow_any_instance_of(User).to receive(:save!).and_wrap_original { |save, *| save.call(validate: false) }
        end

        it "hits the unique index, notifies the owner and answers the same way" do
          allow(User).to receive(:find_by).and_return(nil, existing)

          expect {
            post "/api/v1/auth/register", params: params, as: :json
          }.to have_enqueued_mail(UserMailer, :registration_attempt).and change(User, :count).by(0)

          expect(response).to have_http_status(:accepted)
        end

        it "answers the same way when the competing account is gone" do
          allow(User).to receive(:find_by).and_return(nil, nil)

          expect {
            post "/api/v1/auth/register", params: params, as: :json
          }.not_to have_enqueued_mail

          expect(response).to have_http_status(:accepted)
        end
      end
    end
  end

  describe "POST /api/v1/auth/confirm" do
    let(:user) { create(:user, :unconfirmed) }

    it "confirms, sends the welcome email and signs in" do
      token = user.generate_token_for(:email_confirmation)

      expect {
        post "/api/v1/auth/confirm", params: { token: token }, as: :json
      }.to have_enqueued_mail(UserMailer, :welcome)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "tokens", "access_token")).to be_present
      expect(user.reload).to be_confirmed

      post "/api/v1/auth/confirm", params: { token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an invalid token" do
      post "/api/v1/auth/confirm", params: { token: "lixo" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/auth/confirm/resend" do
    it "always answers 202 and only sends to pending accounts" do
      create(:user, :unconfirmed, email: "pendente@example.com")
      create(:user, email: "ok@example.com")

      expect { post "/api/v1/auth/confirm/resend", params: { email: "pendente@example.com" }, as: :json }
        .to have_enqueued_mail(UserMailer, :confirmation_instructions)
      expect(response).to have_http_status(:accepted)

      expect { post "/api/v1/auth/confirm/resend", params: { email: "ok@example.com" }, as: :json }
        .not_to have_enqueued_mail(UserMailer, :confirmation_instructions)
      expect(response).to have_http_status(:accepted)
    end
  end
end
