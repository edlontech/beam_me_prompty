defmodule BeamMePrompty.Commons.QueryFilter do
  @moduledoc """
  Provides utility functions for dynamically applying filter conditions to Ecto queries.

  This module allows building Ecto queries by adding `where` clauses based on a
  map of filter criteria. It supports various operators and optional field restrictions.
  """

  import Ecto.Query

  @doc """
  Applies a map of filter conditions to an Ecto query.

  It iterates through the `filters` map and adds corresponding `where` clauses
  to the provided `query`. Filters can be applied based on simple equality
  or using various comparison operators. An optional list of allowed fields
  can be provided to restrict which filters are applied.

  ## Parameters

    * `query`: The base `Ecto.Query.t()` to which filters will be added.
    * `filters`: A map containing the filter criteria, or `nil`. Filters can be specified in two formats:
      - `{field :: atom(), value :: any()}`: Applies an equality filter (`field == value`).
      - `{field :: atom(), operator :: atom(), value :: any()}`: Applies a filter based on the specified operator. Supported operators are:
        - `:eq`: Equal to (`==`)
        - `:not_eq`: Not equal to (`!=`)
        * `:gt`: Greater than (`>`)
        * `:gte`: Greater than or equal to (`>=`)
        * `:lt`: Less than (`<`)
        * `:lte`: Less than or equal to (`<=`)
        * `:like`: Case-sensitive pattern matching (`like/2`)
        * `:in`: Checks if the field value is within the given list (`in/2`)
        * `:not_in`: Checks if the field value is not within the given list (`not in/2`)
        * `:is_nil`: Checks if the field value is nil (`is_nil/1`). The `value` is ignored.
        * `:not_nil`: Checks if the field value is not nil (`not is_nil/1`). The `value` is ignored.
    * `allowed_fields`: An optional list of atoms representing the fields that are allowed to be filtered. If `nil` (the default), all fields passed in the `filters` map are considered valid.

  Filters where the value is `nil` (in the `{field, value}` format) are ignored. If an unknown operator is provided in the three-element tuple format, the filter is ignored.

  ## Returns

    * The modified `Ecto.Query.t()` with the applied filters.

  ## Examples

      iex> base_query = from(p in Post, select: p)
      iex> filters = %{status: :published, likes: {:gte, 10}}
      iex> apply_filters(base_query, filters)
      #Ecto.Query<from p in Post, where: p.status == ^:published and p.likes >= ^10, select: p>

      iex> base_query = from(u in User, select: u)
      iex> filters = %{name: "Alice", role: "guest"}
      iex> allowed = [:name]
      iex> apply_filters(base_query, filters, allowed)
      #Ecto.Query<from u in User, where: u.name == ^"Alice", select: u> # role filter ignored
  """
  @spec apply_filters(Ecto.Query.t(), map(), list() | nil) :: Ecto.Query.t()
  def apply_filters(query, filters, allowed_fields \\ nil) do
    Enum.reduce(filters, query, fn
      {_field, nil}, acc_query ->
        acc_query

      {field, value}, acc_query when is_atom(field) ->
        if field_allowed?(field, allowed_fields) do
          where(acc_query, [l], field(l, ^field) == ^value)
        else
          acc_query
        end

      {field, operator, value}, acc_query when is_atom(field) ->
        if field_allowed?(field, allowed_fields) do
          apply_filter_with_operator(acc_query, field, operator, value)
        else
          acc_query
        end
    end)
  end

  defp field_allowed?(_field, nil), do: true

  defp field_allowed?(field, allowed_fields) when is_list(allowed_fields),
    do: field in allowed_fields

  defp apply_filter_with_operator(query, field, operator, value) do
    case operator do
      op when op in [:eq, :not_eq] -> apply_equality_filter(query, field, op, value)
      op when op in [:gt, :gte, :lt, :lte] -> apply_comparison_filter(query, field, op, value)
      op when op in [:in, :not_in] -> apply_membership_filter(query, field, op, value)
      op when op in [:is_nil, :not_nil] -> apply_null_filter(query, field, op)
      :like -> where(query, [l], like(field(l, ^field), ^"%#{value}%"))
      _ -> query
    end
  end

  defp apply_equality_filter(query, field, :eq, value),
    do: where(query, [l], field(l, ^field) == ^value)

  defp apply_equality_filter(query, field, :not_eq, value),
    do: where(query, [l], field(l, ^field) != ^value)

  defp apply_comparison_filter(query, field, :gt, value),
    do: where(query, [l], field(l, ^field) > ^value)

  defp apply_comparison_filter(query, field, :gte, value),
    do: where(query, [l], field(l, ^field) >= ^value)

  defp apply_comparison_filter(query, field, :lt, value),
    do: where(query, [l], field(l, ^field) < ^value)

  defp apply_comparison_filter(query, field, :lte, value),
    do: where(query, [l], field(l, ^field) <= ^value)

  defp apply_membership_filter(query, field, :in, value),
    do: where(query, [l], field(l, ^field) in ^value)

  defp apply_membership_filter(query, field, :not_in, value),
    do: where(query, [l], field(l, ^field) not in ^value)

  defp apply_null_filter(query, field, :is_nil),
    do: where(query, [l], is_nil(field(l, ^field)))

  defp apply_null_filter(query, field, :not_nil),
    do: where(query, [l], not is_nil(field(l, ^field)))
end
