FactoryBot.define do
  factory :payment do
    user
    amount_cents { 15_000 }
    description { "MVP backend, first milestone" }

    trait :pending_pix do
      status { "pending" }
      payment_method { "pix" }
      provider { "mercado_pago" }
      sequence(:provider_payment_id) { |n| (7_000_000 + n).to_s }
    end

    trait :approved do
      status { "approved" }
      payment_method { "card" }
      provider { "mercado_pago" }
      sequence(:provider_payment_id) { |n| (1_000_000 + n).to_s }
      approved_at { Time.current }
    end
  end
end
