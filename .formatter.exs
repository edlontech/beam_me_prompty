[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 98,
  locals_without_parens: [
    agent: 1,
    stage: 1,
    using: 1,
    with_params: 1,
    inputs: 1,
    with_input: 1,
    message: 2,
    expect_output: 1,
    call: 1,
    call: 2
  ],
  export: [
    locals_without_parens: [
      agent: 1,
      stage: 1,
      using: 1,
      with_params: 1,
      inputs: 1,
      with_input: 1,
      message: 2,
      expect_output: 1,
      call: 1,
      call: 2
    ]
  ]
]
