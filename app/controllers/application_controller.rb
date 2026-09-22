class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  # No allow_browser guard, deliberately.
  #
  # Rails generates `allow_browser versions: :modern`, which answers 406 to any
  # browser without webp, web push, badges, import maps, CSS nesting and :has.
  # This app uses none of the first three -- the only mention of them in the
  # codebase was the generated comment on that line -- so it was turning people
  # away over capabilities nothing here calls. Production logged three of them
  # in one session, on /walks and twice on /, which is a phone that could not
  # open the app at all.
  #
  # A walking app is used on whatever phone someone is holding. If a future
  # feature genuinely needs a capability, gate that feature rather than the door.

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])

    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end
end
