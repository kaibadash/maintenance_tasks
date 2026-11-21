# frozen_string_literal: true

require "prism"

module MaintenanceTasks
  # Reads the comment directly above a Task class so the UI can show it as the
  # Task's description. Parsing is defensive: unexpected source returns nil
  # instead of raising.
  #
  # @api private
  class TaskComment
    # Inline comments that are file metadata rather than a description.
    IGNORED_INLINE_COMMENT = %r{
      \A\#\s*
      (?:-\*-\s*)?
      (?:
        frozen_string_literal|
        encoding|
        coding|
        warn_indent|
        shareable_constant_value|
        typed|
        rubocop
      )
      \s*:
    }ix
    private_constant :IGNORED_INLINE_COMMENT

    class << self
      # Returns the description parsed from the leading comment of the named class.
      #
      # @param task_name [String] the name of the class to read.
      # @return [String, nil] the description, or nil when it cannot be read.
      def extract(task_name)
        new(task_name).extract
      rescue StandardError
        nil
      end
    end

    # @param task_name [String] the name of the class to read.
    def initialize(task_name)
      @task_name = task_name
    end

    # @return [String, nil] the description, or nil when it cannot be read.
    def extract
      # Autoload the constant first. Zeitwerk reports its own file as the
      # source location until the referenced class has been loaded.
      return unless @task_name.safe_constantize

      file, line = Object.const_source_location(@task_name)
      return unless file && line && File.file?(file)

      result = Prism.parse_file(file)
      return if result.failure?

      result.attach_comments!
      visitor = Visitor.new(@task_name, line)
      visitor.visit(result.value)
      format(visitor.comments)
    end

    private

    def format(comments)
      return if comments.blank?

      text = comments.filter_map { |comment| comment_body(comment) }.join("\n").strip
      text unless text.empty?
    end

    def comment_body(comment)
      case comment
      when Prism::InlineComment
        return if comment.slice.match?(IGNORED_INLINE_COMMENT)

        comment.slice.sub(/\A# ?/, "").rstrip
      when Prism::EmbDocComment
        comment.slice
          .sub(/\A=begin[^\n]*\n/, "")
          .sub(/\n?=end\s*\z/, "")
          .rstrip
      end
    end

    # Finds the ClassNode Ruby defined for the expected constant. Walking every
    # class covers both nested modules and the compact `class Namespace::Name`
    # syntax, and the source line distinguishes that class from others.
    class Visitor < Prism::Visitor
      # @return [Array<Prism::InlineComment, Prism::EmbDocComment>, nil]
      attr_reader :comments

      # @param task_name [String] the expected class name.
      # @param line [Integer] the line where Ruby defined the class.
      def initialize(task_name, line)
        @simple_name = task_name.split("::").last
        @line = line
        super()
      end

      # @param node [Prism::ClassNode] the class currently being visited.
      def visit_class_node(node)
        if @comments.nil? && node.location.start_line == @line && node.name.to_s == @simple_name
          @comments = node.comments
        end

        super
      end
    end
    private_constant :Visitor
  end
end
