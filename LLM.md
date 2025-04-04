# What we are building

We are building an LLM Orchestrator in Elixir using a DSL approach.

DSL Example:

```elixir
defmodule PromptFlow do
  use BeamMePrompty.Pipeline

  pipeline "topic_extraction" do
    # Stage 1: Initial extraction with GPT-4o-mini
    stage :extraction do
      using model: "gpt-4o-mini-2024-07-18"
      
      with_params max_tokens: 2000, temperature: 0.05
      
      with_context do
        workspace_context: @workspace_context,
        title: @title,
        duration: @duration,
        purpose: @purpose,
        insights: @insights,
        meeting_classification: @meeting_classification,
        meeting_scope: @meeting_scope,
        speakers: @speakers,
        transcript_without_timestamps: @transcript_without_timestamps
      end
      
      message :developer, """
        You are a helpful assistant that is skilled at understanding conversation transcripts...
      """
      
      message :developer, """
        This is the context of the conversation, here you will find metadata...
        
        <context>
          <!-- Workspace information is provided to better help you understand... -->
          <%= @workspace_context %>
          ...
        </context>
      """
      
      # Additional messages...
      
      expect_output schema: %{
        type: :object,
        properties: %{
          categories: %{
            type: :array,
            description: "List of categories",
            items: %{
              # Schema definition...
            }
          }
        },
        required: [:categories]
      }
    end
    
    # Stage 2: Refinement with GPT-4o
    stage :refinement do
      using model: "gpt-4o-2024-11-20"
      
      with_params max_tokens: 3000, temperature: 0.02
      
      with_input from: :extraction, select: :categories
      
      message :developer, """
        You are a smart text formatter that reformats existing hierarchical lists...
      """
      
      # Additional messages...
      
      expect_output schema: %{
        # Output schema...
      }
    end
    
    # Stage 3: Timestamp extraction
    stage :timestamp_extraction do
      using model: "gpt-4o-mini-2024-07-18"
      
      with_params max_tokens: 3000, temperature: 0.02
      
      with_input from: :refinement, select: :categories
      with_context duration: @duration, transcript: @transcript
      
      message :developer, """
        You are specialist in finding similarities between texts...
      """
      
      # Additional messages...
      
      expect_output schema: %{
        # Output schema...
      }
    end
  end
end
```
