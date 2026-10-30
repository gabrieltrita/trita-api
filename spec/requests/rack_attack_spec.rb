require "rails_helper"

RSpec.describe "Rate limiting (Rack::Attack)", type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    example.run
  ensure
    Rack::Attack.enabled = false
  end

  def login_from(ip, email)
    post "/api/v1/auth/login", params: { email: email, password: "Errada@123" }, as: :json, env: { "REMOTE_ADDR" => ip }
  end

  it "throttles by the email in the JSON body, even across different IPs" do
    5.times { |i| login_from("10.0.0.#{i + 1}", "alvo@example.com") }
    expect(response).to have_http_status(:unauthorized)

    login_from("10.0.0.99", "ALVO@example.com")
    expect(response).to have_http_status(:too_many_requests)
    expect(json.dig("error", "code")).to eq("rate_limited")
    expect(response.headers["Retry-After"]).to eq("60")
  end

  it "throttles by IP" do
    10.times { |i| login_from("10.1.1.1", "user#{i}@example.com") }
    login_from("10.1.1.1", "outro@example.com")
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles social login by IP" do
    10.times { post "/api/v1/auth/oauth/google", params: { id_token: "x" }, as: :json, env: { "REMOTE_ADDR" => "10.3.3.3" } }
    post "/api/v1/auth/oauth/google", params: { id_token: "x" }, as: :json, env: { "REMOTE_ADDR" => "10.3.3.3" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles Apple login with the same limit as Google" do
    10.times { post "/api/v1/auth/oauth/apple", params: { id_token: "x" }, as: :json, env: { "REMOTE_ADDR" => "10.5.5.5" } }
    post "/api/v1/auth/oauth/apple", params: { id_token: "x" }, as: :json, env: { "REMOTE_ADDR" => "10.5.5.5" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles linking and unlinking identities with the other re-authenticated actions" do
    user = create(:user)
    5.times { post "/api/v1/me/identities", params: { id_token: "x", current_password: "Errada@123" }, headers: auth_headers(user), as: :json, env: { "REMOTE_ADDR" => "10.4.4.4" } }
    post "/api/v1/me/identities", params: { id_token: "x", current_password: "Errada@123" }, headers: auth_headers(user), as: :json, env: { "REMOTE_ADDR" => "10.4.4.4" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles second factor attempts" do
    5.times { post "/api/v1/auth/two_factor", params: { challenge_token: "x", code: "123456" }, as: :json, env: { "REMOTE_ADDR" => "10.2.2.2" } }
    post "/api/v1/auth/two_factor", params: { challenge_token: "x", code: "123456" }, as: :json, env: { "REMOTE_ADDR" => "10.2.2.2" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles sign-up, confirmation resend and password reset by email across IPs" do
    { "/api/v1/auth/register" => "signup", "/api/v1/auth/confirm/resend" => "resend", "/api/v1/auth/password/forgot" => "forgot" }.each_with_index do |(path, name), index|
      4.times { |i| post path, params: { email: "#{name}@example.com" }, as: :json, env: { "REMOTE_ADDR" => "10.3.#{index}.#{i + 1}" } }

      expect(response).to have_http_status(:too_many_requests), path
      expect(json.dig("error", "code")).to eq("rate_limited")
    end
  end

  it "throttles the health check separately from the general limit" do
    allow(HealthCheck).to receive(:call).and_return(status: "ok", checks: {})
    60.times { get "/health", env: { "REMOTE_ADDR" => "10.4.4.4" } }
    expect(response).to have_http_status(:ok)

    get "/health", env: { "REMOTE_ADDR" => "10.4.4.4" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "keeps the request body readable by Rails" do
    user = create(:user, email: "ok@example.com", password: "Senha@123")
    post "/api/v1/auth/login", params: { email: user.email, password: "Senha@123" }, as: :json
    expect(response).to have_http_status(:ok)
  end
end
