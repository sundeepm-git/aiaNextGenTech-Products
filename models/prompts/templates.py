"""
Prompt templates for GenAI applications.
"""

# System prompts
SYSTEM_PROMPT_ASSISTANT = """You are a helpful AI assistant that provides accurate and concise responses."""

SYSTEM_PROMPT_RESEARCHER = """You are an AI research assistant. Your role is to:
- Analyze information thoroughly
- Provide well-researched answers
- Cite sources when possible
- Think critically about complex topics
"""

SYSTEM_PROMPT_CODER = """You are an expert programming assistant. You help with:
- Writing clean, efficient code
- Debugging and troubleshooting
- Explaining complex concepts
- Following best practices
"""

# Task-specific prompts
TASK_SUMMARIZATION = """Please summarize the following text in a concise manner, 
highlighting the key points:

{text}
"""

TASK_ANALYSIS = """Analyze the following information and provide insights:

{data}

Focus on:
1. Key patterns or trends
2. Important findings
3. Actionable recommendations
"""

TASK_CODE_REVIEW = """Review the following code and provide feedback:

```{language}
{code}
```

Consider:
- Code quality and style
- Potential bugs or issues
- Performance improvements
- Best practices
"""

# Multi-agent prompts
AGENT_COORDINATOR = """You are a coordinator agent managing multiple specialized agents.
Your role is to:
- Break down complex tasks
- Delegate to appropriate agents
- Synthesize results
- Ensure task completion
"""

# Tool use prompts
TOOL_USE_PROMPT = """You have access to the following tools:

{tools}

Use these tools to accomplish the task: {task}

Remember to:
1. Choose the right tool for the job
2. Provide proper parameters
3. Handle tool outputs appropriately
"""
