class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :payable, polymorphic: true, type: :uuid
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "BRL"
      t.string :description, null: false
      t.string :status, null: false, default: "created"
      t.string :payment_method
      t.string :provider
      t.string :provider_payment_id
      t.string :status_detail
      t.integer :installments
      t.string :card_brand
      t.string :card_last_four
      t.text :pix_qr_code
      t.text :pix_qr_code_base64
      t.string :pix_ticket_url
      t.datetime :pix_expires_at
      t.datetime :approved_at
      t.datetime :refunded_at

      t.timestamps
    end

    add_index :payments, [ :user_id, :created_at ]
    add_index :payments, [ :status, :updated_at ]
    add_index :payments, [ :provider, :provider_payment_id ], unique: true, where: "provider_payment_id IS NOT NULL"
  end
end
