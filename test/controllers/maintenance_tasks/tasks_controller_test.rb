# frozen_string_literal: true

require "test_helper"

module MaintenanceTasks
  class TasksControllerTest < ActionDispatch::IntegrationTest
    test "show renders the Task class comment as a description" do
      get task_path("Maintenance::EnqueueErrorTask")

      assert_response :success
      assert_select(
        "p.task-description",
        text: "Any job enqueued for this task errors, see CustomTaskJob.",
      )
    end

    test "show does not render a description when the Task class has no comment" do
      get task_path("Maintenance::UpdatePostsTask")

      assert_response :success
      assert_select "p.task-description", count: 0
    end

    test "show escapes HTML in the Task description" do
      TaskDataShow.any_instance.stubs(:description).returns("<script>alert(1)</script>\n\nArray<String>")

      get task_path("Maintenance::UpdatePostsTask")

      assert_response :success
      assert_select "p.task-description", count: 2
      assert_select "p.task-description", text: "<script>alert(1)</script>"
      assert_select "p.task-description", text: "Array<String>"
      assert_not_includes response.body, "<script>alert(1)</script>"
    end

    private

    def task_path(...) = maintenance_tasks.task_path(...)
  end
end
