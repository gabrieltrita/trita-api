# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_05_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id"
    t.string "action", null: false
    t.string "target_type"
    t.uuid "target_id"
    t.jsonb "metadata", default: {}, null: false
    t.text "ip_address"
    t.text "user_agent"
    t.string "request_id"
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
  end

  create_table "consents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "kind", null: false
    t.string "version", null: false
    t.boolean "granted", null: false
    t.text "ip_address"
    t.text "user_agent"
    t.datetime "created_at", null: false
    t.index ["user_id", "kind", "created_at"], name: "index_consents_on_user_id_and_kind_and_created_at"
    t.index ["user_id"], name: "index_consents_on_user_id"
  end

  create_table "identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "provider", null: false
    t.text "provider_uid", null: false
    t.text "email_at_link"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_uid"], name: "index_identities_on_provider_and_provider_uid", unique: true
    t.index ["user_id", "provider"], name: "index_identities_on_user_id_and_provider", unique: true
  end

  create_table "notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.text "title", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "created_at"], name: "index_notes_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "refresh_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.text "user_agent"
    t.text "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "family_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "session_started_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "revoked_reason"
    t.index ["expires_at"], name: "index_refresh_tokens_on_expires_at"
    t.index ["family_id"], name: "index_refresh_tokens_on_family_id"
    t.index ["token_digest"], name: "index_refresh_tokens_on_token_digest", unique: true
    t.index ["user_id", "revoked_at"], name: "index_refresh_tokens_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "email", null: false
    t.text "first_name", null: false
    t.text "last_name"
    t.text "phone"
    t.string "password_digest"
    t.integer "role", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "password_changed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "confirmed_at"
    t.text "unconfirmed_email"
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.text "otp_secret"
    t.datetime "otp_enabled_at"
    t.bigint "otp_last_used_step"
    t.string "otp_backup_code_digests", default: [], null: false, array: true
    t.datetime "anonymized_at"
    t.datetime "deactivated_at"
    t.string "time_zone", default: "America/Sao_Paulo", null: false
    t.index ["anonymized_at"], name: "index_users_on_anonymized_at"
    t.index ["confirmed_at"], name: "index_users_on_confirmed_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "audit_logs", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "consents", "users", on_delete: :cascade
  add_foreign_key "identities", "users"
  add_foreign_key "notes", "users"
  add_foreign_key "refresh_tokens", "users", on_delete: :cascade
end
