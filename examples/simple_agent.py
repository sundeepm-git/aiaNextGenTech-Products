"""
Simple Agent Example

This example demonstrates how to create a basic AI agent using the aiaNextGenTech framework.
"""

import os
from typing import Optional
from dotenv import load_dotenv

# Load environment variables
load_dotenv()


class SimpleAgent:
    """
    A simple AI agent that can process queries and generate responses.
    
    This is a template for building more complex agents.
    """
    
    def __init__(
        self,
        name: str = "SimpleAgent",
        model: Optional[str] = None,
        temperature: float = 0.7
    ):
        """
        Initialize the agent.
        
        Args:
            name: Name of the agent
            model: LLM model to use (defaults to environment variable)
            temperature: Temperature for response generation
        """
        self.name = name
        self.model = model or os.getenv("DEFAULT_MODEL", "gpt-4")
        self.temperature = temperature
        self.conversation_history = []
        
    def process_query(self, query: str) -> str:
        """
        Process a user query and return a response.
        
        Args:
            query: User's question or request
            
        Returns:
            Agent's response
        """
        # Add query to conversation history
        self.conversation_history.append({
            "role": "user",
            "content": query
        })
        
        # TODO: Implement actual LLM call here
        # This is a placeholder response
        response = f"{self.name} received: {query}"
        
        # Add response to conversation history
        self.conversation_history.append({
            "role": "assistant",
            "content": response
        })
        
        return response
    
    def reset_conversation(self):
        """Reset the conversation history."""
        self.conversation_history = []
        
    def get_history(self) -> list:
        """Get the conversation history."""
        return self.conversation_history


def main():
    """
    Example usage of SimpleAgent.
    """
    print("=" * 50)
    print("Simple Agent Example")
    print("=" * 50)
    
    # Create an agent
    agent = SimpleAgent(name="ExampleAgent")
    
    # Process some queries
    queries = [
        "What can you help me with?",
        "Explain what an AI agent is.",
        "How do you process information?"
    ]
    
    for query in queries:
        print(f"\nUser: {query}")
        response = agent.process_query(query)
        print(f"Agent: {response}")
    
    # Show conversation history
    print("\n" + "=" * 50)
    print("Conversation History:")
    print("=" * 50)
    for i, message in enumerate(agent.get_history(), 1):
        print(f"{i}. {message['role']}: {message['content']}")


if __name__ == "__main__":
    main()
