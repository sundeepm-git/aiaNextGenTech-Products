"""
Base agent class for building AI agents.
"""

from typing import List, Dict, Any, Optional
from abc import ABC, abstractmethod


class BaseAgent(ABC):
    """
    Abstract base class for AI agents.
    
    All agents should inherit from this class and implement the required methods.
    """
    
    def __init__(
        self,
        name: str,
        description: str = "",
        verbose: bool = False
    ):
        """
        Initialize the base agent.
        
        Args:
            name: Name of the agent
            description: Description of agent's capabilities
            verbose: Whether to print verbose output
        """
        self.name = name
        self.description = description
        self.verbose = verbose
        self.conversation_history: List[Dict[str, Any]] = []
        
    @abstractmethod
    def process(self, input_data: Any) -> Any:
        """
        Process input and return output.
        
        This method must be implemented by subclasses.
        
        Args:
            input_data: Input to process
            
        Returns:
            Processed output
        """
        pass
    
    def reset(self):
        """Reset agent state."""
        self.conversation_history = []
        
    def add_to_history(self, role: str, content: str):
        """
        Add a message to conversation history.
        
        Args:
            role: Role of the message sender (user, assistant, system)
            content: Message content
        """
        self.conversation_history.append({
            "role": role,
            "content": content
        })
    
    def get_history(self) -> List[Dict[str, Any]]:
        """
        Get conversation history.
        
        Returns:
            List of conversation messages
        """
        return self.conversation_history
    
    def log(self, message: str):
        """
        Log a message if verbose mode is enabled.
        
        Args:
            message: Message to log
        """
        if self.verbose:
            print(f"[{self.name}] {message}")
