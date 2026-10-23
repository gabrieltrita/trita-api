app = Rails.configuration.x.app
admin_email = ENV.fetch("ADMIN_EMAIL") { "admin@#{app.domain}" }
admin_password = ENV.fetch("ADMIN_PASSWORD") { raise "Set ADMIN_PASSWORD to run the seeds" }

admin = User.find_or_initialize_by(email: admin_email)
if admin.new_record?
  admin.assign_attributes(first_name: "Admin", last_name: app.name, password: admin_password, role: :admin, confirmed_at: Time.current)
  admin.save!
  puts "Admin created: #{admin_email} (set up 2FA via /api/v1/me/two_factor before using the admin area)"
else
  admin.update!(confirmed_at: Time.current) unless admin.confirmed?
  puts "Admin already exists: #{admin_email}"
end

if Rails.env.development? && User.user.count.zero?
  test_email = "user@#{app.domain}"
  User.create!(email: test_email, first_name: "Test", last_name: "User", password: "User@123456", role: :user, confirmed_at: Time.current)
  puts "Test user created: #{test_email} / User@123456"
end
