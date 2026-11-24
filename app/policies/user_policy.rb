class UserPolicy < ApplicationPolicy
  def index? = admin?
  def show? = admin? || own_record?
  def create? = admin?
  def update? = admin? || own_record?

  def destroy? = admin? && !own_record?

  def change_role? = admin? && !own_record?

  def unlock? = admin?

  def reset_two_factor? = admin? && !own_record?

  def deactivate? = admin? && !own_record?

  def reactivate? = admin?

  class Scope < Scope
    def resolve
      user.admin? ? scope.all : scope.where(id: user.id)
    end
  end

  private

  def own_record?
    record.is_a?(User) && record.id == user&.id
  end
end
