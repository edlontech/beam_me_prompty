defmodule BeamMePrompty.Errors do
  @moduledoc """
  Main entry point for the BeamMePrompty error handling system.

  This module configures Splode with error classes and a default handler for unknown errors.
  The error system is organized into four primary error classes:

  - `:external` - Errors originating from external systems or dependencies
  - `:framework` - Errors originating from the framework itself
  - `:invalid` - Errors related to invalid input or state
  - `:unknown` - Unclassified or unexpected errors
  """
  use Splode,
    error_classes: [
      external: BeamMePrompty.Errors.External,
      framework: BeamMePrompty.Errors.Framework,
      invalid: BeamMePrompty.Errors.Invalid,
      unknown: BeamMePrompty.Errors.Unknown
    ],
    unknown_error: BeamMePrompty.Errors.Unknown.Unknown

  @doc false
  def error_classes(), do: @error_classes
end
