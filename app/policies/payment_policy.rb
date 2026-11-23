class PaymentPolicy < ApplicationPolicy
  def index? = true
  def show? = owner?
  def pix? = owner?
  def card? = owner?
  def manage? = admin?

  class Scope < Scope
    def resolve
      scope.where(user: user)
    end
  end

  private

  def owner?
    record.user_id == user.id
  end
end
