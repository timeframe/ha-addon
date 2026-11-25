# frozen_string_literal: true

class RefreshDeviceScreenshotJob < ActiveJob::Base
  queue_as :screenshots
  retry_on StandardError, wait: 30.seconds, attempts: 2

  # Collapse duplicate screenshot refreshes for the same device, but ONLY against
  # jobs that are already due (scheduled_at in the past/unset) or running.
  # Future-scheduled jobs are intentionally NOT counted so a device settings
  # change can still enqueue a sooner refresh while a routine (delayed) job is
  # pending. The running job must not block its own retries.
  before_enqueue do |job|
    throw(:abort) if RefreshDeviceScreenshotJob.ready_job_pending?(job.arguments.first, excluding_job_id: job.job_id)
  end

  def perform(device_id)
    device = Device.find_by(id: device_id)
    return unless device

    device.refresh_screenshot!
  end

  # True when the device already has a due-now or running screenshot job.
  def self.ready_job_pending?(device_id, excluding_job_id: nil)
    jobs = unfinished_jobs
      .where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current)
      .where("serialized_params -> 'arguments' ->> 0 = ?", device_id.to_s)
    jobs = jobs.where("active_job_id IS DISTINCT FROM ?", excluding_job_id) if excluding_job_id
    jobs.exists?
  rescue ActiveRecord::StatementInvalid, NameError
    false
  end

  # Device ids that already have an unfinished screenshot job (ANY schedule).
  # Used to keep the boot-time fan-out idempotent across restarts.
  def self.pending_device_ids
    unfinished_jobs
      .pluck(Arel.sql("serialized_params -> 'arguments' ->> 0"))
      .compact
      .map(&:to_i)
  rescue ActiveRecord::StatementInvalid, NameError
    []
  end

  def self.unfinished_jobs
    GoodJob::Job.where(job_class: name, queue_name: "screenshots", finished_at: nil)
  end
end
