defmodule BeamMePrompty.Errors.Invalid do
  @moduledoc """
  Represents the `:invalid` error class in the BeamMePrompty error handling system.

  This error class is intended for handling errors related to invalid input,
  malformed data, or violations of expected state. It serves as a container for
  more specific error types that indicate issues such as:

  - Validation failures (e.g., `BeamMePrompty.Errors.ValidationError`)
  - Parsing errors of input data (e.g., `BeamMePrompty.Errors.ParsingError`)
  - Constraint violations
  - Scenarios where inputs or system state do not meet expected criteria.

  Errors belonging to this class signify that the problem lies with the data or
  state being processed, rather than an internal framework bug or an external
  system issue.
  """
  @moduledoc section: :error_handling
  use Splode.ErrorClass, class: :invalid
end
