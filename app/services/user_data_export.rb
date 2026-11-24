class UserDataExport
  def initialize(user)
    @user = user
  end

  def as_json(*)
    {
      exported_at: Time.current.iso8601,
      profile: UserBlueprint.render_as_hash(@user, view: :self).merge(
        last_sign_in_at: @user.last_sign_in_at,
        sign_in_count: @user.sign_in_count,
        password_changed_at: @user.password_changed_at,
        confirmed_at: @user.confirmed_at
      ),
      consents: @user.consents.order(:created_at).map do |c|
        { kind: c.kind, version: c.version, granted: c.granted, at: c.created_at, ip_address: c.ip_address, user_agent: c.user_agent }
      end,
      sessions: RefreshToken.sessions_for(@user).map do |s|
        { started_at: s.session_started_at, last_activity_at: s.created_at, ip_address: s.ip_address, user_agent: s.user_agent }
      end,
      activity: AuditLog.involving(@user).recent.limit(1000).map do |log|
        { action: log.action, at: log.created_at, ip_address: log.ip_address, user_agent: log.user_agent }
      end,
      payments: PaymentBlueprint.render_as_hash(@user.payments.recent),
      content: User::PERSONAL_DATA.index_with do |association|
        blueprint_for(association).render_as_hash(@user.public_send(association))
      end
    }
  end

  private

  def blueprint_for(association)
    "#{@user.association(association).klass.name}Blueprint".constantize
  end
end
