require "rails_helper"

RSpec.describe "Admin pagination", type: :request do
  let(:admin) { create(:user, :admin) }

  before { create_list(:user, 24) }

  def users_page(**params)
    get "/api/v1/admin/users", params: params, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    json
  end

  it "defaults to 20 per page with full metadata" do
    body = users_page

    expect(body["data"].size).to eq(20)
    expect(body["meta"]).to eq("page" => 1, "per_page" => 20, "total" => 25, "pages" => 2, "next" => 2, "prev" => nil)
  end

  it "returns the last page with prev set and next nil" do
    body = users_page(page: 2)

    expect(body["data"].size).to eq(5)
    expect(body["meta"]).to include("page" => 2, "next" => nil, "prev" => 1)
  end

  it "honors the limit param" do
    body = users_page(limit: 10, page: 3)

    expect(body["data"].size).to eq(5)
    expect(body["meta"]).to include("per_page" => 10, "pages" => 3, "page" => 3)
  end

  it "caps the limit param at 100" do
    expect(users_page(limit: 500)["meta"]["per_page"]).to eq(100)
  end

  it "serves an empty page beyond the last one instead of failing" do
    body = users_page(page: 9)

    expect(body["data"]).to eq([])
    expect(body["meta"]).to include("page" => 9, "total" => 25, "pages" => 2, "next" => nil)
  end

  it "treats invalid page values as the first page" do
    expect(users_page(page: "abc")["meta"]["page"]).to eq(1)
  end

  it "does not repeat or skip records across pages" do
    ids = users_page(page: 1)["data"].map { |u| u["id"] } + users_page(page: 2)["data"].map { |u| u["id"] }
    expect(ids.size).to eq(25)
    expect(ids.uniq.size).to eq(25)
  end
end
