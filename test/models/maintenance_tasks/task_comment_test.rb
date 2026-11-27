# frozen_string_literal: true

require "test_helper"
require "prism"
require "tempfile"

module MaintenanceTasks
  class TaskCommentTest < ActiveSupport::TestCase
    teardown do
      remove_sample
    end

    test ".extract returns the comment above a nested Task class" do
      load_sample(<<~RUBY)
        module TaskCommentSample
          module Nested
            # Updates every post.
            class Example
            end
          end
        end
      RUBY

      assert_equal(
        "Updates every post.",
        TaskComment.extract("TaskCommentSample::Nested::Example"),
      )
    end

    test ".extract returns the comment above a compact class definition" do
      load_sample(<<~RUBY)
        module TaskCommentSample
        end

        # Rewrites rows.
        # This cannot be undone.
        class TaskCommentSample::Example
        end
      RUBY

      assert_equal(
        "Rewrites rows.\nThis cannot be undone.",
        TaskComment.extract("TaskCommentSample::Example"),
      )
    end

    test ".extract keeps a blank comment line as a paragraph break" do
      load_sample(<<~RUBY)
        module TaskCommentSample
          # Rewrites rows.
          #
          # This cannot be undone.
          class Example
          end
        end
      RUBY

      assert_equal(
        "Rewrites rows.\n\nThis cannot be undone.",
        TaskComment.extract("TaskCommentSample::Example"),
      )
    end

    test ".extract returns the comment for a class with a compact body" do
      load_sample(<<~RUBY)
        module TaskCommentSample
          # Runs once.
          class Example; end
        end
      RUBY

      assert_equal("Runs once.", TaskComment.extract("TaskCommentSample::Example"))
    end

    test ".extract returns an embedded document comment" do
      load_sample(<<~RUBY)
        module TaskCommentSample
        =begin
        Batch update.
        =end
          class Example
          end
        end
      RUBY

      assert_equal("Batch update.", TaskComment.extract("TaskCommentSample::Example"))
    end

    test ".extract returns the comment for the expected class" do
      load_sample(<<~RUBY)
        module TaskCommentSample
          # Other task
          class Other
          end

          # Expected task
          class Example
          end

          # Outer
          class Outer
            # Inner
            class Outer
            end
          end
        end
      RUBY

      assert_equal("Expected task", TaskComment.extract("TaskCommentSample::Example"))
      assert_equal("Outer", TaskComment.extract("TaskCommentSample::Outer"))
      assert_equal("Inner", TaskComment.extract("TaskCommentSample::Outer::Outer"))
    end

    test ".extract ignores comments that are not attached to the class" do
      load_sample(<<~RUBY)
        # Module comment
        module TaskCommentSample
          class Example
          end
        end
      RUBY

      assert_nil TaskComment.extract("TaskCommentSample::Example")
    end

    test ".extract ignores magic comments and RuboCop directives" do
      load_sample(<<~RUBY)
        # frozen_string_literal: true

        module TaskCommentSample
          # typed: true
          # rubocop:disable Style/Documentation
          # encoding: utf-8
          # Deletes expired sessions.
          class Example
          end
        end
      RUBY

      assert_equal(
        "Deletes expired sessions.",
        TaskComment.extract("TaskCommentSample::Example"),
      )
    end

    test ".extract returns nil when the class has no description comment" do
      load_sample(<<~RUBY)
        module TaskCommentSample
        end
      RUBY
      load_sample(<<~RUBY, reset: false)
        # frozen_string_literal: true
        class TaskCommentSample::Example
        end
      RUBY

      assert_nil TaskComment.extract("TaskCommentSample::Example")
    end

    test ".extract reads the comment from an existing Task" do
      assert_equal(
        "Any job enqueued for this task errors, see CustomTaskJob.",
        TaskComment.extract("Maintenance::EnqueueErrorTask"),
      )
      assert_nil TaskComment.extract("Maintenance::UpdatePostsTask")
    end

    test ".extract returns nil when the constant does not exist" do
      assert_nil TaskComment.extract("TaskCommentSample::Missing")
    end

    test ".extract returns nil when the source cannot be parsed" do
      with_broken_constant do |file|
        file.write("class <\n")
        file.flush
        Object.stubs(:const_source_location).with("TaskCommentSample::Broken").returns([file.path, 1])

        assert_nil TaskComment.extract("TaskCommentSample::Broken")
      end
    end

    test ".extract returns nil when reading the source fails" do
      with_broken_constant do |file|
        file.write("class Example\nend\n")
        file.flush
        Object.stubs(:const_source_location).with("TaskCommentSample::Broken").returns([file.path, 1])
        Prism.stubs(:parse_file).raises(StandardError, "boom")

        assert_nil TaskComment.extract("TaskCommentSample::Broken")
      end
    end

    private

    def load_sample(source, reset: true)
      if reset
        remove_sample
      else
        close_sample_file
      end

      @sample_file = Tempfile.new(["task_comment_sample", ".rb"])
      @sample_file.write(source)
      @sample_file.flush
      load(@sample_file.path)
    end

    def remove_sample
      Object.send(:remove_const, :TaskCommentSample) if Object.const_defined?(:TaskCommentSample, false)
      close_sample_file
    end

    def close_sample_file
      return unless @sample_file

      @sample_file.close
      File.unlink(@sample_file.path) if File.exist?(@sample_file.path)
      @sample_file = nil
    end

    def with_broken_constant
      remove_sample
      Object.const_set(:TaskCommentSample, Module.new)
      TaskCommentSample.const_set(:Broken, Class.new)
      file = Tempfile.new(["task_comment_invalid", ".rb"])
      yield file
    ensure
      file&.close
      File.unlink(file.path) if file && File.exist?(file.path)
      remove_sample
    end
  end
end
