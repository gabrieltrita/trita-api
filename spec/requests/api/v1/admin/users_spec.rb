require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  it "blocks regular users" do
    get "/api/v1/admin/users", headers: auth_headers(user)
    expect(response).to have_http_status(:forbidden)
  end

  it "requires the admin to have 2FA enabled" do
    get "/api/v1/admin/users", headers: auth_headers(create(:user, :admin_without_2fa))
    expect(response).to have_http_status(:forbidden)
    expect(json.dig("error", "code")).to eq("two_factor_setup_required")
  end

  it "lists paginated users, excluding anonymized ones" do
    create_list(:user, 3)
    create(:user).anonymize!
    get "/api/v1/admin/users", params: { limit: 2 }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json["data"].size).to eq(2)
    expect(json.dig("meta", "total")).to eq(4)
  end

  it "filters by email" do
    target = create(:user, email: "alvo@example.com")
    get "/api/v1/admin/users", params: { email: "alvo@example.com" }, headers: auth_headers(admin)
    expect(json["data"].map { |u| u["id"] }).to eq([ target.id ])
  end

  it "filters by role and ignores an unknown role" do
    user
    get "/api/v1/admin/users", params: { role: "admin" }, headers: auth_headers(admin)
    expect(json["data"].map { |u| u["id"] }).to eq([ admin.id ])

    get "/api/v1/admin/users", params: { role: "superuser" }, headers: auth_headers(admin)
    expect(json.dig("meta", "total")).to eq(2)
  end

  it "shows a user with the admin view" do
    get "/api/v1/admin/users/#{user.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "id")).to eq(user.id)
    expect(json.dig("data", "email")).to eq(user.email)
  end

  it "creates a confirmed admin and audits it" do
    post "/api/v1/admin/users",
      params: { email: "novoadmin@example.com", first_name: "New", password: "Admin@123", role: "admin" },
      headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)

    created = User.find_by(email: "novoadmin@example.com")
    expect(created).to be_admin
    expect(created).to be_confirmed
    expect(AuditLog.find_by(action: "user.created", target_id: created.id).actor).to eq(admin)
  end

  it "returns per-field errors when creating an invalid user" do
    post "/api/v1/admin/users", params: { email: "not-an-email", password: "short" }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("validation_failed")
    expect(json.dig("error", "details").keys).to include("email", "password")
  end

  it "updates profile fields and audits which fields changed" do
    patch "/api/v1/admin/users/#{user.id}", params: { first_name: "Renamed" }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(user.reload.first_name).to eq("Renamed")
    expect(AuditLog.find_by(action: "user.updated", target_id: user.id).metadata).to eq("fields" => [ "first_name" ])
  end

  it "promotes a user to admin and records who did it" do
    patch "/api/v1/admin/users/#{user.id}", params: { role: "admin" }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload).to be_admin

    log = AuditLog.find_by(action: "user.role_changed", target_id: user.id)
    expect(log.actor).to eq(admin)
    expect(log.metadata).to eq("from" => "user", "to" => "admin")
  end

  it "does not let admins demote themselves" do
    patch "/api/v1/admin/users/#{admin.id}", params: { role: "user" }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects an invalid role" do
    patch "/api/v1/admin/users/#{user.id}", params: { role: "superuser" }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "removes a user by anonymizing their data (LGPD)" do
    delete "/api/v1/admin/users/#{user.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
    expect(user.reload).to be_anonymized
    expect(AuditLog.where(action: "user.anonymized", target_id: user.id)).to exist
  end

  it "does not let admins delete themselves" do
    delete "/api/v1/admin/users/#{admin.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:forbidden)
  end

  it "unlocks an account" do
    5.times { user.register_failed_login! }
    post "/api/v1/admin/users/#{user.id}/unlock", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(user.reload).not_to be_access_locked
    expect(json.dig("data", "locked")).to be(false)
  end

  it "resets 2FA for a user who lost their phone and ends their sessions" do
    target = create(:user, :with_2fa)
    target_tokens = tokens_for(target)

    delete "/api/v1/admin/users/#{target.id}/two_factor", headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
    expect(target.reload).not_to be_two_factor_enabled

    get "/api/v1/me", headers: bearer(target_tokens[:access_token])
    expect(response).to have_http_status(:unauthorized)
  end
end
