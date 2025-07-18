[
  version: "0.7.2",
  # Can also be set/reset with `--autocorrect`/`--no-autocorrect`.
  autocorrect: true,
  # With "--dry" no changes will be written to the files.
  # Can also be set/reset with `--dry`/`--no-dry`.
  # If dry is true then verbose is also active.
  dry: false,
  # Enables or disables color in the output.
  color: true,
  # Can also be set/reset with `--verbose`/`--no-verbose`.
  verbose: false,
  # Can be overwritten by calling `mix recode "lib/**/*.ex"`.
  inputs: ["{mix,.formatter}.exs", "{lib,test}/**/*.{ex,exs}"],
  formatters: [Recode.CLIFormatter],
  tasks: [
    {Recode.Task.AliasExpansion, []},
    {Recode.Task.AliasOrder, []},
    {Recode.Task.Nesting, []},
    {Recode.Task.PipeFunOne, []},
    {Recode.Task.SinglePipe, []},
    {Recode.Task.Specs, [exclude: ["test/**/*.{ex,exs}", "mix.exs"], config: [only: :visible]]}

    # {Recode.Task.Dbg, [autocorrect: false]},
    # {Recode.Task.EnforceLineLength, [active: false]},
    # {Recode.Task.FilterCount, []},
    # {Recode.Task.IOInspect, [autocorrect: false]},
    # {Recode.Task.TagFIXME, [exit_code: 2]},
    # {Recode.Task.TagTODO, [exit_code: 4]},
    # {Recode.Task.TestFileExt, []},
    # {Recode.Task.UnusedVariable, [active: false]}
  ]
]
