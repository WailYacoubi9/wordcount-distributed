#!/bin/bash
# Script pour corriger les line endings (CRLF → LF) dans tous les scripts shell

echo "Correction des line endings pour tous les scripts shell..."

# Trouver tous les fichiers .sh et les convertir
find . -name "*.sh" -type f -exec dos2unix {} \; 2>/dev/null || {
    # Si dos2unix n'est pas disponible, utiliser sed
    echo "dos2unix non trouvé, utilisation de sed..."
    find . -name "*.sh" -type f -exec sed -i 's/\r$//' {} \;
}

# Corriger aussi le Makefile
sed -i 's/\r$//' Makefile 2>/dev/null

echo "✅ Line endings corrigés!"
echo ""
echo "Pour éviter ce problème à l'avenir :"
echo "  git config --global core.autocrlf false"
echo "  git rm --cached -r ."
echo "  git reset --hard"
