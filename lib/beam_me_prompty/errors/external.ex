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

  This module also defines common specific external error types like `APIError` and `NetworkError`.
  """
  @moduledoc section: :error_handling
  use Splode.ErrorClass, class: :external

  defmodule APIError do
    @moduledoc """
    Represents an error that occurred while interacting with an external API.
    """
    @moduledoc section: :error_handling
    use Splode.Error,
      class: :external,
      fields: [
        # HTTP method as an atom (e.g., :get, :post)
        :method,
        # The URL of the API request
        :url,
        # HTTP status code received (integer)
        :status_code,
        # The body of the request (optional)
        :request_body,
        # The body of the response (optional)
        :response_body,
        # A more specific reason or message (optional, string)
        :reason
      ]

    def message(%{reason: reason}) when is_binary(reason), do: reason

    def message(%{method: method, url: url, status_code: status_code}) do
      msg =
        "API Error: #{Atom.to_string(method) |> String.upcase()} #{url} - Status #{status_code}"

      # Consider adding response_body inspection if needed, keeping it concise.
      # For example: msg <> " - Response: #{inspect(response_body, limit: 100)}"
      msg
    end

    def message(params) do
      # Generic fallback message
      "API Error: #{inspect(params, pretty: true, limit: 200)}"
    end
  end

  defmodule NetworkError do
    @moduledoc """
    Represents an error related to network connectivity.
    """
    @moduledoc section: :error_handling
    use Splode.Error,
      class: :external,
      fields: [
        # The primary reason for the network error (atom or string)
        :reason,
        # The target host (optional, string)
        :host,
        # The target port (optional, integer)
        :port,
        # Additional details about the error (optional)
        :details
      ]

    def message(%{reason: reason, host: host, port: port})
        when is_binary(host) and is_integer(port) do
      "Network Error: #{inspect(reason)} when connecting to #{host}:#{port}."
    end

    def message(%{reason: reason, host: host}) when is_binary(host) do
      "Network Error: #{inspect(reason)} for host #{host}."
    end

    def message(%{reason: reason}) do
      "Network Error: #{inspect(reason)}."
    end

    def message(params) do
      # Generic fallback message
      "Network Error: #{inspect(params, pretty: true, limit: 200)}"
    end
  end
end
