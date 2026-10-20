require "test_helper"
require "json"
require "open3"
require "tempfile"
require "yaml"

class DeployGateTest < ActiveSupport::TestCase
  CURRENT_SHA = "a" * 40
  OLD_SHA = "b" * 40

  test "only successful upstream main pushes can deploy automatically" do
    assert_equal({ "deploy" => "true", "sha" => CURRENT_SHA }, decision(workflow_run_event))

    [
      workflow_run_event(conclusion: "failure"),
      workflow_run_event(event: "pull_request"),
      workflow_run_event(branch: "feature"),
      workflow_run_event(repository: "fork/leave-desk"),
      workflow_run_event(sha: OLD_SHA),
      workflow_run_event(sha: "invalid\nsha")
    ].each do |payload|
      assert_equal({ "deploy" => "false" }, decision(payload))
    end
  end

  test "fork pull request named main cannot deploy" do
    payload = workflow_run_event(event: "pull_request", branch: "main",
      repository: "fork/leave-desk")

    assert_equal({ "deploy" => "false" }, decision(payload))
  end

  test "manual dispatch accepts its explicitly selected revision" do
    assert_equal({ "deploy" => "true", "sha" => OLD_SHA },
      decision({}, event_name: "workflow_dispatch", sha: OLD_SHA))
  end

  test "production job is gated by the unprivileged authorization job" do
    workflow = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
    authorize = workflow.fetch("jobs").fetch("authorize")
    deploy = workflow.fetch("jobs").fetch("deploy")

    assert_equal({ "contents" => "read" }, authorize.fetch("permissions"))
    assert_nil authorize["environment"]
    assert_equal "authorize", deploy.fetch("needs")
    assert_equal "needs.authorize.outputs.deploy == 'true'", deploy.fetch("if")
  end

  test "deployment bounds internal health checks and reports deadline expiry" do
    workflow = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
    deploy_steps = workflow.fetch("jobs").fetch("deploy").fetch("steps")
    command = deploy_steps.find { |step| step["name"] == "Deploy tested image" }.fetch("run")

    assert_includes command, "timeout --signal=TERM --kill-after=5s 90s"
    assert_includes command, "Internal health check timed out after 90 seconds"
    assert_includes command, "./current/compose.sh logs --tail=100 web"
  end

  test "release publisher receives all required arguments in one remote command" do
    workflow = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
    deploy_steps = workflow.fetch("jobs").fetch("deploy").fetch("steps")
    command = deploy_steps.find do |step|
      step["name"] == "Publish deployment configuration atomically"
    end.fetch("run")

    assert_includes command,
      "sh '$staging_directory/publish-release.sh' '$deployment_root' " \
      "'$staging_directory' '$RELEASE_ID' '$release_image'"
  end

  test "each build has a unique tag while releases use the build digest" do
    workflow = YAML.load_file(Rails.root.join(".github/workflows/deploy.yml"))
    deploy_steps = workflow.fetch("jobs").fetch("deploy").fetch("steps")
    build = deploy_steps.find { |step| step["name"] == "Build and publish image" }
    publish = deploy_steps.find do |step|
      step["name"] == "Publish deployment configuration atomically"
    end
    tags = build.fetch("with").fetch("tags").lines.map(&:strip)

    assert_equal "build", build.fetch("id")
    assert_includes tags,
      "${{ env.IMAGE_NAME }}:${{ needs.authorize.outputs.sha }}-" \
      "${{ github.run_id }}-${{ github.run_attempt }}"
    assert_not_includes tags, "${{ env.IMAGE_NAME }}:${{ needs.authorize.outputs.sha }}"
    assert_equal "${{ steps.build.outputs.digest }}", publish.fetch("env").fetch("IMAGE_DIGEST")
    assert_equal "${{ needs.authorize.outputs.sha }}-${{ github.run_id }}-" \
      "${{ github.run_attempt }}", publish.fetch("env").fetch("RELEASE_ID")
    assert_includes publish.fetch("run"), 'release_image="$IMAGE_NAME@$IMAGE_DIGEST"'
  end

  private

  def workflow_run_event(conclusion: "success", event: "push", branch: "main",
    repository: "example/leave-desk", sha: CURRENT_SHA)
    {
      "repository" => { "default_branch" => "main" },
      "workflow_run" => {
        "conclusion" => conclusion, "event" => event, "head_branch" => branch,
        "head_repository" => { "full_name" => repository }, "head_sha" => sha
      }
    }
  end

  def decision(payload, event_name: "workflow_run", sha: CURRENT_SHA)
    Tempfile.create("deploy-event") do |event_file|
      event_file.write(JSON.generate(payload))
      event_file.flush
      Tempfile.create("deploy-output") do |output_file|
        environment = {
          "GITHUB_EVENT_NAME" => event_name,
          "GITHUB_EVENT_PATH" => event_file.path,
          "GITHUB_OUTPUT" => output_file.path,
          "GITHUB_REPOSITORY" => "example/leave-desk",
          "GITHUB_SHA" => sha,
          "MAIN_TIP_SHA" => CURRENT_SHA
        }
        _stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby,
          Rails.root.join("bin/deploy-gate").to_s)
        assert status.success?, stderr
        output_file.rewind
        output_file.read.lines.to_h { |line| line.strip.split("=", 2) }
      end
    end
  end
end
