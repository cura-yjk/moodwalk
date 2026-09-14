require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires a name" do
    user = User.new(email: "nameless@example.com", password: "password123")

    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test "requires a unique email" do
    duplicate = User.new(name: "Copy", email: users(:walker).email, password: "password123")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "saved_routes reads through saved_journeys" do
    users(:walker).saved_journeys.create!(journey: journeys(:meguro_loop))

    assert_equal [journeys(:meguro_loop)], users(:walker).reload.saved_routes.to_a
  end
end
