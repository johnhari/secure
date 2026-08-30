
with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# find _buildIconButton start
start_idx = -1
for i, line in enumerate(lines):
    if 'Widget _buildIconButton' in line:
        start_idx = i
        break

if start_idx != -1:
    # find where it should end (before _buildInstrumentSelector)
    end_idx = -1
    for i in range(start_idx, len(lines)):
        if 'Widget _buildInstrumentSelector' in lines[i]:
            end_idx = i
            break
    
    if end_idx != -1:
        new_method = [
            "  Widget _buildIconButton({required IconData icon, required Color color, String? tooltip, required VoidCallback onPressed}) {\n",
            "    final button = Material(\n",
            "      color: Colors.transparent,\n",
            "      child: InkWell(\n",
            "        onTap: onPressed,\n",
            "        borderRadius: BorderRadius.circular(8),\n",
            "        child: Container(\n",
            "          padding: const EdgeInsets.all(8),\n",
            "          decoration: BoxDecoration(\n",
            "            color: color.withValues(alpha: 0.1),\n",
            "            borderRadius: BorderRadius.circular(8),\n",
            "            border: Border.all(color: color.withValues(alpha: 0.2)),\n",
            "          ),\n",
            "          child: Icon(icon, color: color, size: 18),\n",
            "        ),\n",
            "      ),\n",
            "    );\n",
            "\n",
            "    if (tooltip != null) {\n",
            "      return Tooltip(\n",
            "        message: tooltip,\n",
            "        child: button,\n",
            "      );\n",
            "    }\n",
            "    return button;\n",
            "  }\n",
            "\n"
        ]
        
        final_content = lines[:start_idx] + new_method + lines[end_idx:]
        with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart', 'w', encoding='utf-8') as f:
            f.writelines(final_content)
        print("Fixed ChartScreen.")
else:
    print("Could not find _buildIconButton")
