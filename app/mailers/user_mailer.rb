class UserMailer < ApplicationMailer
  def confirmation_instructions(user)
    @user = user
    @url = frontend_url("/confirm-email?token=#{CGI.escape(user.generate_token_for(:email_confirmation))}")
    mail to: @user.email, subject: "Confirm your email"
  end

  def registration_attempt(user)
    @user = user
    @login_url = frontend_url("/login")
    @forgot_url = frontend_url("/forgot-password")
    mail to: @user.email, subject: "Sign-up attempt with your email"
  end

  def welcome(user)
    @user = user
    @login_url = frontend_url("/login")
    mail to: @user.email, subject: "Welcome to #{app.name}!"
  end

  def password_reset(user)
    @user = user
    @url = frontend_url("/reset-password?token=#{CGI.escape(user.generate_token_for(:password_reset))}")
    mail to: @user.email, subject: "Reset your password"
  end

  def password_changed(user)
    @user = user
    @forgot_url = frontend_url("/forgot-password")
    mail to: @user.email, subject: "Your password was changed"
  end

  def email_change_confirmation(user)
    @user = user
    @url = frontend_url("/confirm-email-change?token=#{CGI.escape(user.generate_token_for(:email_change))}")
    mail to: @user.unconfirmed_email, subject: "Confirm your new email"
  end

  def email_change_requested(user)
    @user = user
    @forgot_url = frontend_url("/forgot-password")
    mail to: @user.email, subject: "Email change requested"
  end

  def account_locked(user)
    @user = user
    @locked_until = user.locked_until
    @forgot_url = frontend_url("/forgot-password")
    mail to: @user.email, subject: "Your account was temporarily locked"
  end

  def two_factor_disabled(user)
    @user = user
    @forgot_url = frontend_url("/forgot-password")
    mail to: @user.email, subject: "Two-factor authentication disabled"
  end
end
