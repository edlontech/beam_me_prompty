defmodule BeamMePrompty.Commons.KeysetPagination do
  @moduledoc """
  Provides utilities for implementing keyset (cursor-based) pagination with Ecto queries.

  Keyset pagination avoids the performance issues of offset-based pagination on large
  datasets by using the values of the last fetched item as a cursor for the next query.

  This implementation assumes a stable sort order based primarily on `:inserted_at` (descending)
  and secondarily on `:id` (descending) as a tie-breaker.
  """
  import Ecto.Query

  @doc """
  Applies keyset pagination logic to an Ecto query.

  It orders the query by `inserted_at` (desc) and `id` (desc), applies a `WHERE` clause
  based on the `next_after` cursor (if provided), and limits the results to `page_size`.

  ## Parameters

    * `query` (Ecto.Query.t()): The base Ecto query.
    * `next_after` (map() | nil): A map containing the cursor values from the last item
      of the previous page, typically `%{inserted_at: value, id: value}`. If `nil`,
      fetches the first page.
    * `page_size` (integer()): The maximum number of results to return per page.

  ## Returns

    * `Ecto.Query.t()`: The modified Ecto query ready for fetching the next page.

  ## Examples

      iex> base_query = Log |> Ecto.Query.from()
      iex> page_size = 20
      iex> # First page request
      iex> first_page_query = apply_pagination(base_query, nil, page_size)
      # Ecto.Query<from l in Log, order_by: [desc: l.inserted_at, desc: l.id], limit: ^20>

      iex> # Assume last log of first page was %{inserted_at: ~N[...], id: 100}
      iex> cursor = %{inserted_at: last_log.inserted_at, id: last_log.id}
      iex> # Second page request
      iex> second_page_query = apply_pagination(base_query, cursor, page_size)
      # Ecto.Query<from l in Log, where: l.inserted_at < ^cursor.inserted_at or (l.inserted_at == ^cursor.inserted_at and l.id < ^cursor.id), order_by: [desc: l.inserted_at, desc: l.id], limit: ^20>
  """
  @spec apply_pagination(Ecto.Query.t(), map() | nil, integer()) :: Ecto.Query.t()
  def apply_pagination(query, next_after, page_size) do
    query = order_by(query, [l], desc: l.inserted_at, desc: l.id)

    query =
      if is_map(next_after) && Map.has_key?(next_after, :inserted_at) &&
           Map.has_key?(next_after, :id) do
        after_inserted_at = next_after.inserted_at
        after_id = next_after.id

        where(
          query,
          [l],
          l.inserted_at < ^after_inserted_at or
            (l.inserted_at == ^after_inserted_at and l.id < ^after_id)
        )
      else
        query
      end

    limit(query, ^page_size)
  end

  @doc """
  Calculates the `next_after` cursor based on the results of the current page.

  If the number of returned items matches the `page_size`, it implies there might
  be more data. In this case, it extracts the `inserted_at` and `id` from the
  *last* item in the list to be used as the cursor for the *next* page request.
  Otherwise, it returns `nil`, indicating the end of the data.

  ## Parameters

    * `logs` ([map()]): The list of results fetched for the current page.
    * `page_size` (integer()): The requested page size for the query that produced `logs`.

  ## Returns

    * `map() | nil`: A map `%{inserted_at: value, id: value}` representing the cursor
      for the next page, or `nil` if the current page was the last one.

  ## Example

      iex> page_size = 10
      iex> full_page_logs = Enum.map(1..10, &%{id: &1, inserted_at: DateTime.utc_now()})
      iex> calculate_next_after(full_page_logs, page_size)
      %{inserted_at: last_log.inserted_at, id: 10} # Assuming id 10 was the last

      iex> partial_page_logs = Enum.map(1..5, &%{id: &1, inserted_at: DateTime.utc_now()})
      iex> calculate_next_after(partial_page_logs, page_size)
      nil
  """
  @spec calculate_next_after([map()], integer()) :: map() | nil
  def calculate_next_after(logs, page_size) do
    if length(logs) == page_size do
      last_log = List.last(logs)
      %{inserted_at: last_log.inserted_at, id: last_log.id}
    else
      nil
    end
  end
end
