defmodule BeamMePrompty.ValidatorTest do
  use ExUnit.Case

  alias BeamMePrompty.Validator

  describe "validate/2" do
    test "validates simple schema successfully" do
      schema = %{
        name: :string,
        age: :integer
      }

      data = %{
        name: "John Doe",
        age: 30
      }

      assert {:ok, validated_data} = Validator.validate(schema, data)
      assert validated_data == data
    end

    test "returns error for invalid data" do
      schema = %{
        name: :string,
        age: {:integer, {:range, {18, 120}}}
      }

      data = %{
        name: "John Doe",
        age: 150
      }

      assert {:error, errors} = Validator.validate(schema, data)
      assert is_list(errors.cause)
      assert length(errors.cause) > 0
      assert Enum.any?(errors.cause, &String.contains?(&1, "range"))
    end

    test "handles required fields" do
      schema = %{
        name: {:required, :string},
        email: {:required, :string}
      }

      # Missing required field
      data = %{
        name: "John Doe"
      }

      assert {:error, errors} = Validator.validate(schema, data)
      assert is_list(errors.cause)
      assert Enum.any?(errors.cause, &String.contains?(&1, "required"))
    end

    test "handles nested schemas" do
      schema = %{
        user: %{
          name: :string,
          address: %{
            street: :string,
            city: :string
          }
        }
      }

      data = %{
        user: %{
          name: "John Doe",
          address: %{
            street: "123 Main St",
            # Should be a string
            city: 12345
          }
        }
      }

      assert {:error, errors} = Validator.validate(schema, data)
      assert is_list(errors.cause)

      # Check if we got errors
      assert length(errors.cause) > 0

      # Just make sure we got some error messages
      assert Enum.all?(errors.cause, fn error ->
               is_binary(error) and String.length(error) > 0
             end)
    end

    test "handles nil schema" do
      data = %{name: "John", age: 30}
      assert {:ok, ^data} = Validator.validate(nil, data)
    end

    test "handles invalid input format" do
      schema = %{name: :string}
      assert {:error, _} = Validator.validate(schema, "not a map")
    end
  end
end
