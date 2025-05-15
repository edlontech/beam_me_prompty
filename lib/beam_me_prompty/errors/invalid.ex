defmodule BeamMePrompty.Errors.Invalid do
  @moduledoc """
  Represents the `:invalid` error class in the BeamMePrompty error handling system.

  This error class is intended for handling errors related to invalid input or state.
  It serves as a container for more specific error types that indicate validation
  failures, constraint violations, or other scenarios where inputs or system state
  do not meet expected criteria.
  """
  use Splode.ErrorClass, class: :invalid
end
