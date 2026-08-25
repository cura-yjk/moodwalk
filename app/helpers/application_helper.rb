module ApplicationHelper
  def active_icon_class(path)
    "highlight-icon" if current_page?(path)
  end
end
