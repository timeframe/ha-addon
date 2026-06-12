# frozen_string_literal: true

require "test_helper"

class RecordUptimeJobTest < ActiveSupport::TestCase
  def setup
    UptimeCheck.delete_all
  end

  FakeApi = Struct.new(:healthy) do
    def states_healthy? = healthy
    def calendars_healthy? = healthy
    def config_healthy? = healthy
    def weather_healthy? = healthy
  end

  test "records a heartbeat for the current minute" do
    HomeAssistantApi.stub(:new, FakeApi.new(true)) do
      RecordUptimeJob.new.perform
    end

    assert_equal 1, UptimeCheck.count
    assert_equal Time.current.utc.beginning_of_minute, UptimeCheck.first.recorded_at
  end

  test "marks healthy when all HA domain checks pass" do
    HomeAssistantApi.stub(:new, FakeApi.new(true)) do
      RecordUptimeJob.new.perform
    end

    assert UptimeCheck.last.healthy?
  end

  test "marks unhealthy when a HA domain check fails" do
    HomeAssistantApi.stub(:new, FakeApi.new(false)) do
      RecordUptimeJob.new.perform
    end

    refute UptimeCheck.last.healthy?
  end

  test "marks unhealthy and still records when the HA API raises" do
    HomeAssistantApi.stub(:new, ->(*) { raise "boom" }) do
      RecordUptimeJob.new.perform
    end

    assert_equal 1, UptimeCheck.count
    refute UptimeCheck.last.healthy?
  end
end
