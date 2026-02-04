# Read the file
with open('tf_refactor_variable.py', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Remove all lines that contain literal \n or \" escape sequences
# These are invalid Python and need to be removed
lines = content.split('\n')
cleaned_lines = []

for line in lines:
    # Skip lines that contain literal \n or \" (not actual newlines/quotes)
    if r'\n' in line or r'\"' in line:
        print(f"Skipping corrupted line: {line[:80]}...")
        continue
    cleaned_lines.append(line)

content = '\n'.join(cleaned_lines)

# Write back
with open('tf_refactor_variable.py', 'w', encoding='utf-8') as f:
    f.write(content)

print('File fixed successfully!')
