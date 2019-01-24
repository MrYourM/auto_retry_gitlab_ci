#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'logger'
require 'byebug'

SCRIPT_NAME = File.basename($PROGRAM_NAME, '.rb')
SCRIPT_RUNNING_FILE = "/tmp/#{SCRIPT_NAME}.lock"
LOG_FILE = "/tmp/#{SCRIPT_NAME}.log"

@remove_script_running_file = true
@all_pipelines_passing = {}
@logger = Logger.new(LOG_FILE)

# Base curl command for GitLab API
#
# @param uri [String] URI for API
# @param request [Symbol] Either :get [default] or :post
# @return [Array<Hash>] API response
def api(uri, request = :get)
  JSON.parse(
    `curl --request #{request.to_s.upcase} -s -S --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_BASE_URL/api/v4/#{uri}"`
  )
end

# List of project IDs belonging to current authenticated user
#
# @return [Array<Integer>] Project IDs
def projects
  @projects ||= begin
    user = api('user')
    api("users/#{user['id']}/projects").sort_by { |p| p['id'] }
  end
end

# Exit the script if it's already running
#
# @return [void]
def exit_if_already_running
  if File.file?(SCRIPT_RUNNING_FILE)
    @remove_script_running_file = false
    exit 0
  end
end

# Exit the script when all jobs passing
#
# @return [void]
def exit_if_all_pipelines_passing
  exit 0 if @all_pipelines_passing.values.all? { |passing| passing == true }
end

# Get the last 20 available jobs
#
# @note 20 is the max number of jobs returned by GitLab
#
# @param project_id [Integer] Project ID
# @return [Array<Hash>] Last 20 available jobs
def last_20_jobs(project_id)
  api("projects/#{project_id}/jobs").sort_by { |j| -j['id'] }
end

# Get only the latest jobs per branch
#
# @param project_id [Integer] Project ID
# @return [Hash] Latest jobs per branch
def latest_jobs(project_id)
  last_20_jobs(project_id).each_with_object({}) do |job, all_latest_jobs|
    branch = job['ref']
    job_name = job['name']
    all_latest_jobs[branch] = {} if all_latest_jobs[branch].nil?
    all_latest_jobs[branch][job_name] = job if all_latest_jobs[branch][job_name].nil?
  end
end

# Get only the latest unpassing jobs per branch
#
# @param project_id [Integer] Project ID
# @return [Array<Hash>] Latest unpassing jobs per branch
def latest_unpassing_jobs(project_id)
  latest_jobs(project_id).each_with_object([]) do |(branch, job_names), unpassing_jobs|
    job_names.each do |job_name, job|
      unpassing_jobs << job unless job['status'] == 'success'
    end
  end
end

# Get the last 20 available pipelines
#
# @note 20 is the max number of pipelines returned by GitLab
#
# @param project_id [Integer] Project ID
# @return [Array<Hash>] Last 20 available pipelines
def last_20_pipelines(project_id)
  api("projects/#{project_id}/pipelines")
end

# Get only the latest pipeline per branch
#
# @param project_id [Integer] Project ID
# @return [Hash] Latest pipeline per branch
def latest_pipelines(project_id)
  last_20_pipelines(project_id).each_with_object({}) do |pipeline, all_latest_pipelines|
    branch = pipeline['ref']
    all_latest_pipelines[branch] = pipeline if all_latest_pipelines[branch].nil?
  end
end

# Get the last unpassing jobs on a pipeline
#
# @param project_id [Integer] Project ID
# @return [Array<Hash>] Latest unpassing pipelines
def latest_unpassing_pipelines(project_id)
  latest_pipelines(project_id).each_with_object([]) do |(branch, pipeline), unpassing_pipelines|
    next if pipeline['status'] == 'success'
    unpassing_pipelines << pipeline
  end
end

# Retry latest failing jobs
#
# @return [Boolean] true if there are still unpassing pipelines, else false
def retry_failing_jobs
  projects.each do |project|
    project_id = project['id']
    @logger.info "Checking Project ##{project_id} \"#{project['name']}\"..."

    unpassing_jobs = latest_unpassing_jobs(project_id)
    unpassing_pipelines = latest_unpassing_pipelines(project_id)

    if unpassing_pipelines.empty?
      @all_pipelines_passing[project_id] = true
      @logger.info '- All pipelines passing'
    else
      @all_pipelines_passing[project_id] = false
    end

    if !unpassing_jobs.empty? && !unpassing_pipelines.empty?
      unpassing_jobs.each do |job|
        message = "- Job ##{job['id']} ('#{job['name']}') "\
                    "on branch '#{job['ref']}' has status %s"
        if ['failed', 'canceled', 'manual'].include?(job['status'])
          # Rerun individual jobs
          @logger.info format(message, "'#{job['status']}'. Retrying...")
          api("projects/#{project_id}/jobs/#{job['id']}/retry", :post)
        else
          @logger.info format(message, "'#{job['status']}'. Skipping retry.")
        end
      end
    else
      unpassing_pipelines.each do |pipeline|
        message = "- Pipeline ##{pipeline['id']} on branch "\
                    "'#{pipeline['ref']}' has status %s"
        if ['failed', 'canceled', 'manual'].include?(pipeline['status'])
          # Rerun the whole pipeline
          @logger.info format(message, "'#{pipeline['status']}'. Retrying...")
          api("projects/#{project_id}/pipelines/#{pipeline['id']}/retry", :post)
        else
          @logger.info format(message, "'#{pipeline['status']}'. Skipping retry.")
        end
      end
    end
  end

  exit_if_all_pipelines_passing
end

begin
  exit_if_already_running

  while true
    # Create tmp file to show that script is running
    FileUtils.touch(SCRIPT_RUNNING_FILE) unless File.file?(SCRIPT_RUNNING_FILE)

    @logger.info "*** CURRENT TIME: #{Time.now} ***"
    retry_failing_jobs
    sleep 60*2
  end
ensure
  # Remove tmp file to show that script is running
  # Note that only the process that created the file can remove it
  FileUtils.rm_f(SCRIPT_RUNNING_FILE) if @remove_script_running_file
end
