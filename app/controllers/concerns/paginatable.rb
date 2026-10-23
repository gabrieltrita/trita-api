module Paginatable
  extend ActiveSupport::Concern

  private

  def pagination_meta(pagy)
    {
      page: pagy.page,
      per_page: pagy.limit,
      total: pagy.count,
      pages: pagy.pages,
      next: pagy.next,
      prev: pagy.previous
    }
  end
end
