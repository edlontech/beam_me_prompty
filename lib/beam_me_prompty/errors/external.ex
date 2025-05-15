defmodule BeamMePrompty.Errors.External do
  @moduledoc """
  Represents the `:external` error class in the BeamMePrompty error handling system.

  This error class is specifically designed for handling errors that originate from
  external systems or dependencies. These errors typically represent failures in
  third-party services, APIs, databases, or other external resources that the
  BeamMePrompty application interacts with.

  ## Common External Error Scenarios

  This error class is appropriate for errors such as:

  - API request failures
  - Database connection issues
  - Third-party service unavailability
  - Network timeouts
  - External authentication failures
  - Rate limiting by external services
  """
  use Splode.ErrorClass, class: :external
end
