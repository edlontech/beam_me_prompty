defmodule BeamMePrompty.Errors do
  use Splode,
    error_classes: [
      external: BeamMePrompty.Errors.External,
      framework: BeamMePrompty.Errors.Framework,
      invalid: BeamMePrompty.Errors.Invalid,
      unknown: BeamMePrompty.Errors.Unknown
    ],
    unknown_error: BeamMePrompty.Errors.Unknown.Unknown
end
