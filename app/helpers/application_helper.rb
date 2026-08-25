module ApplicationHelper
  def time_based_greeting
    current_time = Time.current.hour
    message = ""
    if current_time.between?(0, 12)
      message = "Good Morning"
    elsif current_time.between?(12, 18)
      message = "Good Afternoon"
    else
      message = "Good Evening"
    end
    message
    # current_time
  end
end
