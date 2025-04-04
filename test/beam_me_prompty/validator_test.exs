defmodule BeamMePrompty.ValidatorTest do
  use ExUnit.Case

  alias BeamMePrompty.Validator
  alias OpenApiSpex.Schema

  describe "validate/2" do
    test "validates simple schema successfully" do
      schema = %Schema{
        title: "Simple Schema",
        type: :object,
        properties: %{
          name: %Schema{type: :string, description: "Name of the person"},
          age: %Schema{type: :integer, description: "Age of the person"}
        },
        required: [:name, :age]
      }

      data = %{
        name: "John Doe",
        age: 30
      }

      assert {:ok, validated_data} = Validator.validate(schema, data)
      assert validated_data == data
    end

    test "returns error for invalid data" do
      schema = %Schema{
        title: "Schema with Range",
        type: :object,
        properties: %{
          name: %Schema{type: :string, description: "Name of the person"},
          age: %Schema{
            type: :integer,
            description: "Age of the person",
            minimum: 18,
            maximum: 120
          }
        },
        required: [:name, :age]
      }

      data = %{
        name: "John Doe",
        age: 150
      }

      assert {:error, errors} = Validator.validate(schema, data)
      assert is_list(errors.cause)
      assert length(errors.cause) > 0
      assert Enum.any?(errors.cause, &String.contains?(&1, "maximum"))
    end

    test "handles required fields" do
      schema = %Schema{
        title: "Required Fields Schema",
        type: :object,
        properties: %{
          name: %Schema{type: :string, description: "Name of the person"},
          email: %Schema{type: :string, description: "Email address", format: :email}
        },
        required: [:name, :email]
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
      schema = %Schema{
        title: "Nested Schema",
        type: :object,
        properties: %{
          user: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string, description: "Name of the user"},
              address: %Schema{
                type: :object,
                properties: %{
                  street: %Schema{type: :string, description: "Street address"},
                  city: %Schema{type: :string, description: "City name"}
                },
                required: [:street, :city]
              }
            },
            required: [:name, :address]
          }
        },
        required: [:user]
      }

      data = %{
        user: %{
          name: "John Doe",
          address: %{
            street: "123 Main St",
            # Should be a string
            city: 12_345
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
      schema = %Schema{
        title: "Invalid Input Schema",
        type: :object,
        properties: %{
          name: %Schema{type: :string, description: "Name of the person"}
        },
        required: [:name]
      }

      assert {:error, _} = Validator.validate(schema, "not a map")
    end
  end
end
