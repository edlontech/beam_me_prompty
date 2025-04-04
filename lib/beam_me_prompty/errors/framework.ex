defmodule BeamMePrompty.Errors.Framework do
  @moduledoc """
  Represents the `:framework` error class in the BeamMePrompty error handling system.

  This error class is specifically designed for handling errors that originate from
  within the framework itself. These errors typically represent internal failures,
  configuration issues, or other problems within the BeamMePrompty framework components.
  """
  @moduledoc section: :error_handling
  use Splode.ErrorClass, class: :framework
end
