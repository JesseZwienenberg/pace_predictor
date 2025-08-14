require "test_helper"

class InsightsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get insights_url
    assert_response :success
  end
end
