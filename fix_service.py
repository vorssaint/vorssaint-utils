with open('Sources/Vorssaint/Services/InactiveAppService.swift', 'r') as f:
    content = f.read()

# Let's just find the first physicalFootprint method and keep it, and remove all the extra garbage at the end.
import re
match = re.search(r'    private static func physicalFootprint.*?^}$', content, re.MULTILINE | re.DOTALL)
if match:
    pass # Wait, it's easier to just rebuild the file.
