with open('Sources/Vorssaint/Services/InactiveAppService.swift', 'r') as f:
    lines = f.readlines()

with open('Sources/Vorssaint/Services/InactiveAppService.swift', 'w') as f:
    for line in lines:
        if line.strip() == '}':
            if 'ProcessUsageService already tracks memory' in lines[lines.index(line) + 2]:
                continue
        f.write(line)
