import re

file_path = "Sources/Vorssaint/Core/FeatureHubStrings.swift"
with open(file_path, "r") as f:
    content = f.read()

translations = {
    "de": {
        "nameFinderDeleteShortcuts": "Tastenkürzel für Finder-Löschen",
        "descFinderDeleteShortcuts": "Löschen mit Backspace"
    },
    "fr": {
        "nameFinderDeleteShortcuts": "Raccourcis de suppression Finder",
        "descFinderDeleteShortcuts": "Supprimer avec Retour arrière"
    },
    "it": {
        "nameFinderDeleteShortcuts": "Scorciatoie di eliminazione Finder",
        "descFinderDeleteShortcuts": "Elimina con Backspace"
    },
    "ja": {
        "nameFinderDeleteShortcuts": "Finderの削除ショートカット",
        "descFinderDeleteShortcuts": "Backspaceで削除"
    },
    "zhHans": {
        "nameFinderDeleteShortcuts": "访达删除快捷键",
        "descFinderDeleteShortcuts": "使用退格键删除"
    },
    "zhTW": {
        "nameFinderDeleteShortcuts": "Finder 刪除捷徑",
        "descFinderDeleteShortcuts": "使用倒退鍵刪除"
    },
    "zhHK": {
        "nameFinderDeleteShortcuts": "Finder 刪除捷徑",
        "descFinderDeleteShortcuts": "使用退格鍵刪除"
    },
    "es": {
        "nameFinderDeleteShortcuts": "Atajos de eliminación del Finder",
        "descFinderDeleteShortcuts": "Eliminar con Retroceso"
    },
    "tr": {
        "nameFinderDeleteShortcuts": "Finder Silme Kısayolları",
        "descFinderDeleteShortcuts": "Backspace ile Sil"
    },
    "ko": {
        "nameFinderDeleteShortcuts": "Finder 삭제 단축키",
        "descFinderDeleteShortcuts": "백스페이스로 삭제"
    },
    "ru": {
        "nameFinderDeleteShortcuts": "Ярлыки удаления Finder",
        "descFinderDeleteShortcuts": "Удалить с помощью Backspace"
    }
}

for lang, trans in translations.items():
    # Regex to find the block for the specific language
    # Example: static let de = FeatureHubStrings( ... )
    pattern = r'(static let ' + lang + r' = FeatureHubStrings\([\s\S]*?nameFinderDeleteShortcuts: )"[^"]*"(,\s*descFinderDeleteShortcuts: )"[^"]*"'
    
    replacement = r'\1"' + trans["nameFinderDeleteShortcuts"] + r'"\2"' + trans["descFinderDeleteShortcuts"] + r'"'
    
    content = re.sub(pattern, replacement, content)

with open(file_path, "w") as f:
    f.write(content)

