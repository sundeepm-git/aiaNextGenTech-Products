"""
Example agent using the BaseAgent class.
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from agents.base import BaseAgent


class EchoAgent(BaseAgent):
    """
    A simple echo agent that repeats user input with a prefix.
    
    This demonstrates how to extend the BaseAgent class.
    """
    
    def __init__(self, name: str = "EchoAgent", prefix: str = "Echo: "):
        """
        Initialize the echo agent.
        
        Args:
            name: Name of the agent
            prefix: Prefix to add to echoed messages
        """
        super().__init__(
            name=name,
            description="An agent that echoes user input",
            verbose=True
        )
        self.prefix = prefix
    
    def process(self, input_data: str) -> str:
        """
        Process input by echoing it with a prefix.
        
        Args:
            input_data: User input string
            
        Returns:
            Echoed string with prefix
        """
        self.log(f"Received input: {input_data}")
        
        # Add to conversation history
        self.add_to_history("user", input_data)
        
        # Process the input
        response = f"{self.prefix}{input_data}"
        
        # Add response to history
        self.add_to_history("assistant", response)
        
        self.log(f"Generated response: {response}")
        
        return response


def main():
    """
    Demonstrate the EchoAgent.
    """
    print("=" * 60)
    print("Echo Agent Example - Using BaseAgent")
    print("=" * 60)
    print()
    
    # Create an echo agent
    agent = EchoAgent(prefix="🤖 Echo: ")
    
    # Test inputs
    test_inputs = [
        "Hello, AI agent!",
        "How are you today?",
        "Tell me about yourself."
    ]
    
    # Process each input
    for i, user_input in enumerate(test_inputs, 1):
        print(f"\n--- Interaction {i} ---")
        print(f"User: {user_input}")
        response = agent.process(user_input)
        print(f"Agent: {response}")
    
    # Show conversation history
    print("\n" + "=" * 60)
    print("Complete Conversation History")
    print("=" * 60)
    
    history = agent.get_history()
    for i, message in enumerate(history, 1):
        role = message['role'].capitalize()
        content = message['content']
        print(f"{i}. {role}: {content}")
    
    # Demonstrate reset
    print("\n" + "=" * 60)
    print("Resetting Agent...")
    print("=" * 60)
    agent.reset()
    print(f"History after reset: {len(agent.get_history())} messages")


if __name__ == "__main__":
    main()
