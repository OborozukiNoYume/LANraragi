import os

def generate_tree(startpath, output_file):
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(f"# Project Tree for {os.path.basename(startpath)}\n\n")
        f.write("```\n")
        for root, dirs, files in os.walk(startpath):
            # Calculate level
            level = root.replace(startpath, '').count(os.sep)
            indent = ' ' * 4 * (level)
            dirname = os.path.basename(root)
            
            # Write directory name (if it's the root, use explicit name or just dot)
            if root == startpath:
                f.write(f".\n")
            else:
                 f.write(f"{indent}{dirname}/\n")
            
            subindent = ' ' * 4 * (level + 1)
            
            # Sort for consistent output
            files.sort()
            dirs.sort()

            # Write files
            for file in files:
                if not file.startswith('.'): # Skip hidden files
                    f.write(f"{subindent}{file}\n")
            
            # Prune directories (modify dirs in-place)
            # This prevents os.walk from traversing into these directories
            dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ['node_modules', '__pycache__', 'vendor']]
            
        f.write("```\n")
    print(f"Tree generated at {output_file}")

if __name__ == "__main__":
    # Use the current working directory or a specific path
    project_root = r'e:\Projects\LANraragi'
    output_path = os.path.join(project_root, 'docs', 'project_tree.md')
    generate_tree(project_root, output_path)
